# Fetch BSB display Strong's groupings + build Strong's lexicon for word study.
# Run from repo root or this script's directory.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if ((Split-Path -Leaf $Root) -ne "server") {
  $Root = Join-Path $PSScriptRoot ".."
}
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Data = Join-Path $Root "data\word_study"
$Clone = Join-Path $Data "bsb-data-output"
$Display = Join-Path $Data "display"
$Lexicon = Join-Path $Data "lexicon"

New-Item -ItemType Directory -Force -Path $Lexicon | Out-Null

if (-not (Test-Path (Join-Path $Clone "base\display"))) {
  if (Test-Path $Clone) { Remove-Item -Recurse -Force $Clone }
  git clone --depth 1 --filter=blob:none --sparse https://github.com/BSB-publishing/bsb-data-output.git $Clone
  Push-Location $Clone
  git sparse-checkout set base/display
  Pop-Location
}

if (Test-Path $Display) { Remove-Item -Recurse -Force $Display }
cmd /c mklink /J "$Display" "$Clone\base\display" | Out-Null

$hebUrl = "https://raw.githubusercontent.com/openscriptures/strongs/master/hebrew/strongs-hebrew-dictionary.js"
$grkUrl = "https://raw.githubusercontent.com/openscriptures/strongs/master/greek/strongs-greek-dictionary.js"
Invoke-WebRequest -Uri $hebUrl -OutFile (Join-Path $Lexicon "strongs-hebrew-dictionary.js") -UseBasicParsing
Invoke-WebRequest -Uri $grkUrl -OutFile (Join-Path $Lexicon "strongs-greek-dictionary.js") -UseBasicParsing

python -c @"
import json
from pathlib import Path
lex = Path(r'$Lexicon')
out = {}
for name in ['strongs-hebrew-dictionary.js', 'strongs-greek-dictionary.js']:
    text = (lex / name).read_text(encoding='utf-8')
    start, end = text.find('{'), text.rfind('}')
    data = json.loads(text[start:end+1])
    for key, val in data.items():
        out[key] = {
            'lemma': val.get('lemma') or '',
            'definition': (val.get('strongs_def') or val.get('kjv_def') or '').strip('{} '),
        }
(lex / 'strongs.json').write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
print('lexicon entries', len(out))
"@

Write-Host "Word study data ready under $Data"
