#!/usr/bin/env python3
"""Generate checked-in runtime strings from the English-source String Catalog."""
from pathlib import Path
import json, plistlib, re
resources = Path(__file__).resolve().parents[1] / 'Resources'
catalog = json.loads((resources / 'Localizable.xcstrings').read_text())
assert catalog['sourceLanguage'] == 'en'
for lang in ('en', 'ru'):
    strings, plurals = {}, {}
    for key, entry in catalog['strings'].items():
        value = entry['localizations'][lang]
        if 'stringUnit' in value:
            strings[key] = value['stringUnit']['value']
        else:
            variations = value['variations']['plural']
            # All plural forms use the count as the first argument. Leave later arguments positional.
            plurals[key] = {'NSStringLocalizedFormatKey': '%#@count@', 'count': {
                'NSStringFormatSpecTypeKey': 'NSStringPluralRuleType',
                'NSStringFormatValueTypeKey': 'ld',
                **{category: form['stringUnit']['value'] for category, form in variations.items()}}}
    def quote(text): return json.dumps(text, ensure_ascii=False)
    (resources / f'{lang}.lproj/Localizable.strings').write_text('\n'.join(f'{quote(k)} = {quote(v)};' for k,v in sorted(strings.items())) + '\n')
    (resources / f'{lang}.lproj/Localizable.stringsdict').write_bytes(plistlib.dumps(plurals, sort_keys=False))
print(f'Generated {len(catalog["strings"])} strings for English and Russian')
