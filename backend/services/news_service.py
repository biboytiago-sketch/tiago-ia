import feedparser
from datetime import datetime
import os

RSS_FEEDS = {
    "esportes": {
        "Ge Globo": "https://ge.globo.com/rss/globofutebol/",
        "UOL Esporte": "https://www.uol.com.br/esporte/rss.xml",
        "Lance": "https://www.lance.com.br/rss.xml"
    },
    "cripto": {
        "CoinDesk": "https://www.coindesk.com/arc/outboundfeeds/rss/",
        "Cointelegraph": "https://cointelegraph.com/rss"
    }
}


def buscar_noticias_tempo_real(termo: str):
    noticias = []
    termo_lower = termo.lower()

    for categoria, feeds in RSS_FEEDS.items():
        for fonte, url in feeds.items():
            try:
                feed = feedparser.parse(url)
                for entry in feed.entries:
                    titulo = getattr(entry, "title", "")
                    link = getattr(entry, "link", "")
                    published = getattr(entry, "published", "")

                    contem_termo = (
                        termo_lower in titulo.lower() or
                        termo_lower in fonte.lower() or
                        termo_lower in categoria
                    )

                    if contem_termo or termo == "todas":
                        try:
                            data = datetime(*entry.published_parsed[:6]).isoformat()
                        except Exception:
                            data = datetime.now().isoformat()

                        noticias.append({
                            "titulo": titulo,
                            "link": link,
                            "fonte": fonte,
                            "data": data,
                            "categoria": categoria
                        })

            except Exception as e:
                print(f"Erro ao processar feed {fonte}: {e}")
                continue

    return noticias
