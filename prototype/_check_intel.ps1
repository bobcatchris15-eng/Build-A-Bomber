$lines = Get-Content 'E:\Kitbash-Command\prototype\scripts\battle\hud\intel_feed.gd' -Encoding utf8
'{0} lines total' -f $lines.Count
for ($i = 0; $i -lt 70; $i++) {
    '{0,4}: {1}' -f ($i + 1), $lines[$i]
}
