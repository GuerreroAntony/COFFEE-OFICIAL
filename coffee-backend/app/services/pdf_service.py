"""
PDF generation service using ReportLab.
Generates resumo and mindmap PDFs for gravações.
"""
from __future__ import annotations

import io
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle


# Brand colors for mind map branches
_BRANCH_COLORS = [
    colors.HexColor("#6B4226"),  # coffee brown
    colors.HexColor("#D4A574"),  # latte
    colors.HexColor("#2E7D32"),  # green
    colors.HexColor("#1565C0"),  # blue
]


def _get_styles():
    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(
        name="CoffeeTitle",
        parent=styles["Title"],
        fontSize=20,
        spaceAfter=12,
        textColor=colors.HexColor("#6B4226"),
    ))
    styles.add(ParagraphStyle(
        name="CoffeeSubtitle",
        parent=styles["Heading2"],
        fontSize=14,
        spaceAfter=8,
        textColor=colors.HexColor("#333333"),
    ))
    styles.add(ParagraphStyle(
        name="CoffeeBody",
        parent=styles["Normal"],
        fontSize=11,
        spaceAfter=6,
        leading=14,
    ))
    styles.add(ParagraphStyle(
        name="CoffeeBullet",
        parent=styles["Normal"],
        fontSize=10,
        leftIndent=20,
        spaceAfter=4,
        leading=13,
    ))
    styles.add(ParagraphStyle(
        name="CoffeeHeader",
        parent=styles["Normal"],
        fontSize=8,
        textColor=colors.gray,
    ))
    return styles


def generate_resumo_pdf(gravacao: dict) -> bytes:
    """
    Generate a PDF with the gravação summary.
    gravacao must have: short_summary, full_summary (list of {titulo/title, conteudo/bullets}), date.
    """
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, topMargin=2*cm, bottomMargin=2*cm)
    styles = _get_styles()
    story = []

    # Header
    story.append(Paragraph("Coffee — Resumo de Aula", styles["CoffeeHeader"]))
    story.append(Spacer(1, 0.5*cm))

    # Date
    date_str = ""
    if gravacao.get("date"):
        d = gravacao["date"]
        date_str = d.strftime("%d/%m/%Y") if hasattr(d, "strftime") else str(d)

    story.append(Paragraph(f"Resumo — {date_str}", styles["CoffeeTitle"]))

    # Short summary
    if gravacao.get("short_summary"):
        story.append(Paragraph(gravacao["short_summary"], styles["CoffeeBody"]))
        story.append(Spacer(1, 0.5*cm))

    # Full summary sections
    full_summary = gravacao.get("full_summary")
    if full_summary:
        import json
        if isinstance(full_summary, str):
            full_summary = json.loads(full_summary)
        if isinstance(full_summary, list):
            for section in full_summary:
                title = section.get("titulo") or section.get("title", "")
                story.append(Paragraph(title, styles["CoffeeSubtitle"]))

                content = section.get("conteudo", "")
                bullets = section.get("bullets", [])
                if isinstance(content, str) and content:
                    bullets = [content]

                for bullet in bullets:
                    story.append(Paragraph(f"\u2022 {bullet}", styles["CoffeeBullet"]))
                story.append(Spacer(1, 0.3*cm))

    doc.build(story)
    return buf.getvalue()


def generate_mindmap_pdf(gravacao: dict) -> bytes:
    """
    Generate a PDF with the gravação mind map.
    gravacao must have: mind_map ({topic, branches: [{topic, color, children}]}).
    """
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, topMargin=2*cm, bottomMargin=2*cm)
    styles = _get_styles()
    story = []

    mind_map = gravacao.get("mind_map", {})
    import json
    if isinstance(mind_map, str):
        mind_map = json.loads(mind_map)

    # Header
    story.append(Paragraph("Coffee — Mapa Mental", styles["CoffeeHeader"]))
    story.append(Spacer(1, 0.5*cm))

    # Central topic
    central_topic = mind_map.get("topic", "Mapa Mental")
    story.append(Paragraph(central_topic, styles["CoffeeTitle"]))
    story.append(Spacer(1, 0.5*cm))

    # Branches
    branches = mind_map.get("branches", [])
    for branch in branches:
        color_idx = branch.get("color", 0) % len(_BRANCH_COLORS)
        branch_color = _BRANCH_COLORS[color_idx]

        branch_style = ParagraphStyle(
            name=f"Branch_{color_idx}",
            parent=styles["CoffeeSubtitle"],
            textColor=branch_color,
            fontSize=13,
            spaceAfter=6,
        )
        story.append(Paragraph(branch.get("topic", ""), branch_style))

        children = branch.get("children", [])
        child_style = ParagraphStyle(
            name=f"Child_{color_idx}",
            parent=styles["CoffeeBullet"],
            textColor=colors.HexColor("#444444"),
        )
        for child in children:
            story.append(Paragraph(f"\u2022 {child}", child_style))

        story.append(Spacer(1, 0.4*cm))

    doc.build(story)
    return buf.getvalue()
