#!/usr/bin/env bash
# Uma linha com a cota do Kimi Code (janela de 5 h e mês, cada uma com o zera em hora local). Sai com 3 se alguma passar de 80%.
cred=$(ls "$HOME"/.kimi-code/credentials/kimi-code-env-*.json 2>/dev/null | head -1)
[ -n "$cred" ] || { echo "kimi: sem credencial"; exit 2; }
command -v php >/dev/null 2>&1 || { echo "kimi: precisa de php no PATH para ler a cota"; exit 2; }
busca() {
  local tok
  tok=$(php -r 'echo json_decode(file_get_contents($argv[1]),true)["access_token"] ?? "";' "$(command -v cygpath >/dev/null 2>&1 && cygpath -w "$cred" || printf '%s' "$cred")")
  curl -s -m 20 -H "Authorization: Bearer $tok" https://api.kimi.ai/coding/v1/usages
}
resp=$(busca)
# Token de acesso expira em minutos: uma chamada mínima do CLI o renova.
case "$resp" in *'"usages"'*) ;; *) kimi -p "Responda apenas: ok" >/dev/null 2>&1; resp=$(busca) ;; esac
printf '%s' "$resp" | php -r '
$j = json_decode(stream_get_contents(STDIN), true);
if (! isset($j["usages"])) { echo "kimi: cota ilegível (token expirado? rode kimi uma vez)\n"; exit(2); }
$u = $j["usages"];
$tz = new DateTimeZone(getenv("TZ") ?: date_default_timezone_get());
$h = (new DateTime($u["limit_5h"]["reset_time"]))->setTimezone($tz)->format("H:i");
$fim = (new DateTime($u["limit_month_total"]["reset_time"]))->setTimezone($tz);
$mes = $u["limit_month_total"]["used_ratio"] * 100;
printf("kimi: 5h %d%% (zera %s) · mês %d%% (zera %s)\n", $u["limit_5h"]["used_ratio"] * 100, $h, $mes, $fim->format("Y-m-d H:i"));
exit(($u["limit_5h"]["used_ratio"] > 0.8 || $u["limit_month_total"]["used_ratio"] > 0.8) ? 3 : 0);'
