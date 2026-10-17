#!/bin/sh
cd /home/claude/sim
{ cat shell.html; echo '<script>'; cat engine.js; echo; cat settle.js; echo; cat data.js; echo; sed -e '/\/\*@@STUDENT@@\*\//{r student.js' -e 'd}' ui.js; echo '</script>'; } > dist/kvs-sanal-hasta.html
wc -c dist/kvs-sanal-hasta.html
