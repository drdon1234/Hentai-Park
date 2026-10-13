"""离线词包构建：使用 OpenCC t2s 将审校译文统一为简体。"""
import json
from pathlib import Path
from opencc import OpenCC

root = Path(__file__).resolve().parents[1]
converter = OpenCC('t2s')
for file in sorted((root / 'assets/tag_translations').glob('*/zh-Hans.json')):
    data = json.loads(file.read_text(encoding='utf-8'))
    data['tags'] = {key: converter.convert(value) for key, value in data['tags'].items()}
    file.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
