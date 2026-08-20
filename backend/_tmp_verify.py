import os, sys, json

def carregar_dotenv_manual(path='.env'):
    if not os.path.exists(path):
        return
    with open(path, 'r', encoding='utf-8') as f:
        for linha in f:
            linha = linha.strip()
            if not linha or linha.startswith('#') or '=' not in linha:
                continue
            k, v = linha.split('=', 1)
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            os.environ[k] = v

carregar_dotenv_manual('.env')
sys.path.insert(0, os.getcwd())

from services.live_sports_service import check_fontes_status, obter_jogos_ao_vivo

print("=== 1) CHECK FONTES ===")
r = check_fontes_status(live_probe=True)
print(json.dumps({k:v for k,v in r.items() if k!='fontes'}, indent=2, ensure_ascii=False))
print()
print("=== 2) TESTE obter_jogos_ao_vivo() ===")
jogos = obter_jogos_ao_vivo()
print(f"  Total de jogos retornados: {len(jogos)}")
if jogos:
    print(f"  Fonte utilizada (primeiro jogo): {jogos[0].get('origem_dados','?')}")
    for j in jogos[:5]:
        print(f"     - {j.get('time_casa','?')} x {j.get('time_visitante','?')} "
              f"[{j.get('placar_casa','?')}-{j.get('placar_visitante','?')}] "
              f"status={j.get('status','?')} campeonato={j.get('campeonato','?')[:25]}")
else:
    print("  NENHUM JOGO RETORNADO (caiu fallback vazio!)")
