import json, sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
with open('sinais_render.json', 'rb') as f:
    raw = f.read()
text = raw.decode('utf-16')
d = json.loads(text)
print('total:', d.get('total'))
print('fonte:', repr(d.get('fonte')))
print('totais:', d.get('totais'))
sinais = d.get('sinais', [])
print('qtd sinais na lista:', len(sinais))
ligas = {}
confiancas = []
recomendacoes = {}
for s in sinais:
    liga = s.get('liga') or s.get('league') or s.get('categoria') or '?'
    ligas[liga] = ligas.get(liga, 0) + 1
    c = s.get('confianca') or s.get('confidence') or 0
    confiancas.append(c)
    rec = s.get('recomendacao') or s.get('recommendation') or s.get('decisao') or '?'
    recomendacoes[rec] = recomendacoes.get(rec, 0) + 1
print('\nLigas encontradas:')
for k, v in sorted(ligas.items(), key=lambda x: -x[1]):
    print(f'  {v:3d}  {k}')
print('\nRecomendacoes:')
for k, v in sorted(recomendacoes.items(), key=lambda x: -x[1]):
    print(f'  {v:3d}  {k}')
print('\nRange confianca: min=%s  max=%s  media=%.1f' % (min(confiancas) if confiancas else '?', max(confiancas) if confiancas else '?', (sum(confiancas)/len(confiancas)) if confiancas else 0))
print('\n--- TODOS OS SINAIS ---')
for i, s in enumerate(sinais):
    print(f'{i+1:2d}. {s.get("home")} x {s.get("away")} | {s.get("liga")} | conf={s.get("confianca")} | rec={s.get("recomendacao")} | mercado={s.get("mercado")}')
