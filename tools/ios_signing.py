"""配置 CI 临时 iOS 签名；凭据仅从环境读取，产物只放 test/signing。"""

import base64
import datetime
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SIGNING = ROOT / 'test' / 'signing'
CONFIG = ROOT / 'ios' / 'Flutter' / 'Signing.xcconfig'


def run(*args):
    # security 工具异常时也不回显可能包含密码的命令参数。
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError('iOS 签名工具执行失败，请检查证书、密码与描述文件')
    return result.stdout


def prepare():
    names = ['IOS_CERTIFICATE_BASE64', 'IOS_CERTIFICATE_PASSWORD', 'IOS_PROVISIONING_PROFILE_BASE64']
    values = [os.environ.get(name, '') for name in names]
    if not any(values):
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream:
            stream.write('IOS_SIGNED=false\n')
        return
    if not all(values):
        raise ValueError('iOS 签名配置不完整，必须同时配置证书、密码和描述文件')
    SIGNING.mkdir(parents=True, exist_ok=True)
    certificate = SIGNING / 'certificate.p12'
    profile_file = SIGNING / 'profile.mobileprovision'
    certificate.write_bytes(base64.b64decode(values[0], validate=True))
    profile_file.write_bytes(base64.b64decode(values[2], validate=True))
    profile = plistlib.loads(run('security', 'cms', '-D', '-i', str(profile_file)))
    if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError('iOS 描述文件已过期')
    team = profile['TeamIdentifier'][0]
    identifier = profile['Entitlements']['application-identifier'].split('.', 1)[1]
    uuid = profile['UUID']
    if not re.fullmatch(r'[A-Z0-9]+', team) or not re.fullmatch(r'[A-Za-z0-9.-]+', identifier):
        raise ValueError('描述文件必须绑定明确的 Bundle ID，不支持通配符')
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', uuid):
        raise ValueError('描述文件 UUID 无效')
    method = ('debugging' if profile['Entitlements'].get('get-task-allow') else
              'enterprise' if profile.get('ProvisionsAllDevices') else
              'release-testing' if profile.get('ProvisionedDevices') else 'app-store-connect')
    # 状态先写入，以便任一步骤失败后 always() 清理已创建的材料。
    keychain = Path(os.environ['RUNNER_TEMP']) / 'park-ios.keychain-db'
    profiles = Path.home() / 'Library' / 'Developer' / 'Xcode' / 'UserData' / 'Provisioning Profiles'
    profiles.mkdir(parents=True, exist_ok=True)
    installed = profiles / f'{uuid}.mobileprovision'
    if installed.exists() or keychain.exists():
        raise ValueError('签名临时位置已被占用，拒绝覆盖')
    # 保留原搜索列表，避免清理时改变 runner 的其他签名环境。
    search = run('security', 'list-keychains', '-d', 'user').decode().splitlines()
    search = [line.strip().strip('"') for line in search if line.strip()]
    (SIGNING / 'state.plist').write_bytes(plistlib.dumps({
        'keychain': str(keychain), 'profile': str(installed), 'search': search,
    }))
    password = secrets.token_hex(24)
    run('security', 'create-keychain', '-p', password, str(keychain))
    run('security', 'set-keychain-settings', '-lut', '21600', str(keychain))
    run('security', 'unlock-keychain', '-p', password, str(keychain))
    run('security', 'import', str(certificate), '-P', values[1], '-A', '-t', 'cert', '-f', 'pkcs12', '-k', str(keychain))
    run('security', 'list-keychains', '-d', 'user', '-s', str(keychain), *search)
    run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain))
    shutil.copyfile(profile_file, installed)
    CONFIG.write_text(
        f'CODE_SIGN_STYLE = Manual\nDEVELOPMENT_TEAM = {team}\n'
        f'PRODUCT_BUNDLE_IDENTIFIER = {identifier}\nPROVISIONING_PROFILE_SPECIFIER = {uuid}\n'
        f'CODE_SIGN_IDENTITY = {"Apple Development" if method == "debugging" else "Apple Distribution"}\n',
        encoding='utf-8', newline='\n',
    )
    (SIGNING / 'ExportOptions.plist').write_bytes(plistlib.dumps({
        'method': method, 'teamID': team, 'signingStyle': 'manual',
        'provisioningProfiles': {identifier: uuid},
        'uploadSymbols': False, 'manageAppVersionAndBuildNumber': False,
    }))
    with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as stream:
        stream.write('IOS_SIGNED=true\n')


def cleanup():
    state_file = SIGNING / 'state.plist'
    failed = False
    try:
        if state_file.exists():
            state = plistlib.loads(state_file.read_bytes())
            keychain = Path(state['keychain'])
            actions = [lambda: run('security', 'list-keychains', '-d', 'user', '-s', *state['search'])]
            if keychain.exists():
                actions.append(lambda: run('security', 'delete-keychain', str(keychain)))
            actions.append(lambda: Path(state['profile']).unlink(missing_ok=True))
            for action in actions:
                try:
                    action()
                except Exception:
                    failed = True
    finally:
        CONFIG.unlink(missing_ok=True)
        if SIGNING.exists():
            shutil.rmtree(SIGNING)
    if failed:
        raise RuntimeError('部分系统签名材料清理失败；仓库内临时材料已删除')


if __name__ == '__main__':
    try:
        {'prepare': prepare, 'cleanup': cleanup}[sys.argv[1]]()
    except Exception as error:
        # 不输出 subprocess 参数或原始凭据。
        print(str(error) if isinstance(error, (ValueError, RuntimeError)) else 'iOS 签名配置失败', file=sys.stderr)
        sys.exit(1)
