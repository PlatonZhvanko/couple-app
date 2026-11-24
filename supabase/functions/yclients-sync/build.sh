#!/bin/sh
# Собирает logic.js из logic.ts (его скачивает загрузчик index.ts из репозитория).
# Запуск: npm i typescript (один раз), затем sh build.sh
cd "$(dirname "$0")" && node -e '
const ts=require("typescript"),fs=require("fs");
const out=ts.transpileModule(fs.readFileSync("logic.ts","utf8"),{compilerOptions:{target:"ES2022",module:"None"}});
fs.writeFileSync("logic.js",out.outputText+"\n");'
