import json
d = json.load(open('/tmp/models.json'))
for m in d.get('models', []):
    name = m['name']
    if 'live' in name or 'native' in name or ('flash' in name and 'tts' not in name):
        print(name, m.get('supportedGenerationMethods'))
