"""只简化中文译文，不转换原名或日语专名。"""
import json
from pathlib import Path
from opencc import OpenCC

root = Path(__file__).resolve().parents[1]
converter = OpenCC('t2s')
for file in sorted((root / 'assets/tag_translations').glob('*/zh-Hans.json')):
    data = json.loads(file.read_text(encoding='utf-8'))
    changed = False
    for key, value in data['tags'].items():
        # 原名可能含汉字，不能把日语名称转成简繁混写。
        original = value.lower()
        namespace = key.partition(':')[0]
        if (key == original or key.endswith(':' + original)
                or any('\u3040' <= c <= '\u30ff' for c in value)
                or namespace in {'artist', 'group', 'cosplayer', 'author', 'authors',
                                 'model', 'models', 'maker', 'actor', 'actress', '作者', '厂商', '女优'}):
            continue
        simplified = converter.convert(value)
        if simplified != value:
            changed = True
            data['tags'][key] = simplified
    if changed:
        version = data['version'].split('.')
        version[2] = str(int(version[2]) + 1)
        data['version'] = '.'.join(version)
        file.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
