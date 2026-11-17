W = "https://en.wikipedia.org/wiki/"
def D(cat, sub, headline, body, src, url, quiz=None, prompt=None, evergreen=False):
    return {"category": cat, "subcategory": sub, "headline": headline, "body": body,
            "sourceTitle": src, "sourceURL": url,
            "quiz": ({"question": quiz[0], "options": quiz[1], "answer": quiz[2]} if quiz else None),
            "prompt": prompt, "evergreen": evergreen, "version": 1}
