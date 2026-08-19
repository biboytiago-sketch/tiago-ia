from services.news_service import buscar_noticias_tempo_real


def scraper_sports_news(termos: list[str] | None = None,
                        max_noticias: int = 6) -> list[dict]:
    termos = termos or ["Flamengo", "Palmeiras", "Brasileirão",
                        "São Paulo", "Corinthians", "Santos", "Grêmio",
                        "Inter", "Cruzeiro", "Atlético"]
    acum: list[dict] = []
    vistos: set[str] = set()
    for termo in termos:
        try:
            for noticia in buscar_noticias_tempo_real(termo):
                chave = f"{noticia.get('fonte','')}|{noticia.get('titulo','')}"
                if chave in vistos:
                    continue
                vistos.add(chave)
                acum.append(noticia)
                if len(acum) >= max_noticias:
                    return acum
        except Exception:
            continue
    return acum[:max_noticias]


def noticias_por_jogo(home_name: str, away_name: str,
                      liga_name: str = "Brasileirão") -> list[dict]:
    termos = [f"{home_name} x {away_name}", home_name, away_name, liga_name,
              f"{home_name} lesão", f"{away_name} desfalque",
              f"{home_name} suspens", f"{away_name} clima"]
    return scraper_sports_news(termos=termos, max_noticias=4)
