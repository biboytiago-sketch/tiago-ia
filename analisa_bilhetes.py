import json, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
with open('bilhetes_render.json', 'rb') as f:
    raw = f.read()
text = raw.decode('utf-16') if raw[:2] == b'\xff\xfe' else raw.decode('utf-8')
d = json.loads(text)
print('origem_dados_geral:', d.get('origem_dados_geral'))
print('total_jogos_pool:', d.get('total_jogos_pool'))
bs = d.get('bilhetes_sugeridos') or []
print('qtd bilhetes:', len(bs))
for b in bs:
    perf = b.get('perfil','?')
    qtd = b.get('quantidade_jogos','?')
    odd = b.get('odds_acumulada_ia','?')
    prob = b.get('probabilidade_geral_ia_pct','?')
    sel = b.get('selecoes') or []
    print(f'\n=== PERFIL {perf} ({qtd} jogos, odd={odd}, prob={prob}%) ===')
    for i, s in enumerate(sel):
        liga = s.get('liga')
        if isinstance(liga, dict):
            liga = liga.get('name') or str(liga)
        se = s.get('selecao_escolhida') or {}
        print(f'  {i+1}. {s.get("time_casa")} x {s.get("time_fora")} | {liga} | mercado={se.get("mercado")} op={se.get("opcao_escolhida")} odd={se.get("odd_alvo")} prob={se.get("probabilidade_pct")}% conf_ia={se.get("score_ia")}')
