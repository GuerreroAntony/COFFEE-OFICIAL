import { useState, useEffect } from "react";

const fontLink = document.createElement("link");
fontLink.href = "https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700&display=swap";
fontLink.rel = "stylesheet";
document.head.appendChild(fontLink);

const FONT = "'Poppins', sans-serif";

const LECTURES = [
  {
    label: "Marketing",
    date: "25 fev",
    professor: "Prof. Ana Silva",
    data: {
      topic: "Mix de Marketing",
      branches: [
        { topic: "Produto", color: 0, children: ["Qualidade e Design", "Ciclo de Vida", "Marca e Embalagem"] },
        { topic: "Preço", color: 1, children: ["Precificação", "Elasticidade", "Preço Psicológico"] },
        { topic: "Praça", color: 2, children: ["Canais de Distrib.", "Logística", "E-commerce"] },
        { topic: "Promoção", color: 3, children: ["Publicidade", "Marketing Digital", "Relações Públicas"] },
      ],
    },
  },
  {
    label: "Contabilidade",
    date: "26 fev",
    professor: "Prof. Ricardo Mendes",
    data: {
      topic: "Demonstrações Contábeis",
      branches: [
        { topic: "Balanço Patrim.", color: 0, children: ["Ativos", "Passivos", "Patrimônio Líquido"] },
        { topic: "DRE", color: 1, children: ["Receitas", "Custos e Despesas", "Lucro Líquido"] },
        { topic: "Fluxo de Caixa", color: 2, children: ["Operacional", "Investimento", "Financiamento"] },
        { topic: "DMPL", color: 3, children: ["Capital Social", "Reservas", "Dividendos"] },
      ],
    },
  },
  {
    label: "Consumidor",
    date: "27 fev",
    professor: "Profª. Carla Duarte",
    data: {
      topic: "Comportamento do Consumidor",
      branches: [
        { topic: "Culturais", color: 0, children: ["Cultura", "Subcultura", "Classe Social"] },
        { topic: "Sociais", color: 1, children: ["Grupos de Ref.", "Família", "Papéis e Status"] },
        { topic: "Pessoais", color: 2, children: ["Idade e Estágio", "Estilo de Vida", "Personalidade"] },
        { topic: "Psicológicos", color: 3, children: ["Motivação", "Percepção", "Aprendizagem"] },
      ],
    },
  },
];

const PALETTE = [
  { main: "#E8453C", soft: "#FEF0EF", softBorder: "#FACBC8", leafHover: "#FDE3E1" },
  { main: "#E8943C", soft: "#FEF5EE", softBorder: "#FAD9B5", leafHover: "#FCECD8" },
  { main: "#2BAC76", soft: "#EDF9F2", softBorder: "#A8E0C4", leafHover: "#DDF3E8" },
  { main: "#6C5CE7", soft: "#F1EFFE", softBorder: "#C3B8F7", leafHover: "#E5E0FC" },
];

// Approximate text width for Poppins at a given font size
function textWidth(str, fontSize, fontWeight = 500) {
  const avg = fontWeight >= 600 ? fontSize * 0.62 : fontSize * 0.56;
  return str.length * avg;
}

const PAD_H = 28; // horizontal padding each side
const PAD_V_ROOT = 16;
const PAD_V_BRANCH = 14;
const PAD_V_LEAF = 12;

const ROOT_FONT = 12.5;
const BRANCH_FONT = 11.5;
const LEAF_FONT = 9.5;

const BRANCH_Y = 180;
const LEAF_START_Y = 270;
const LEAF_GAP = 50;

function smoothPath(x1, y1, x2, y2) {
  const midY = y1 + (y2 - y1) * 0.5;
  return `M${x1},${y1} C${x1},${midY} ${x2},${midY} ${x2},${y2}`;
}

function MindMap({ data, animKey }) {
  const [hovered, setHovered] = useState(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    setVisible(false);
    const t = setTimeout(() => setVisible(true), 50);
    return () => clearTimeout(t);
  }, [animKey]);

  // Compute root dimensions
  const rootTW = textWidth(data.topic, ROOT_FONT, 600);
  const rootW = rootTW + PAD_H * 2;
  const rootH = ROOT_FONT + PAD_V_ROOT * 2;
  const rootX = 450;
  const rootY = 52;

  // Compute branch X positions — evenly distributed
  const branchCount = data.branches.length;
  const branchXs = data.branches.map((_, i) => {
    const margin = 100;
    const spread = 900 - margin * 2;
    return margin + (spread / (branchCount - 1)) * i;
  });

  return (
    <div style={{
      width: "100%", overflowX: "auto",
      opacity: visible ? 1 : 0,
      transform: visible ? "none" : "translateY(6px)",
      transition: "opacity 0.4s ease, transform 0.4s ease",
      padding: "24px 12px",
    }}>
      <svg viewBox="0 0 900 520" style={{ width: "100%", display: "block", minWidth: 680 }}>
        {/* Lines */}
        {data.branches.map((branch, bi) => {
          const bx = branchXs[bi];
          const p = PALETTE[branch.color];
          return (
            <g key={`c-${bi}`}>
              <path
                d={smoothPath(rootX, rootY + rootH / 2, bx, BRANCH_Y - (BRANCH_FONT + PAD_V_BRANCH * 2) / 2)}
                fill="none" stroke={p.main} strokeWidth="2"
                opacity="0.18" strokeLinecap="round"
              />
              {branch.children.map((_, li) => {
                const ly = LEAF_START_Y + li * LEAF_GAP;
                const branchH = BRANCH_FONT + PAD_V_BRANCH * 2;
                return (
                  <path key={li}
                    d={smoothPath(bx, BRANCH_Y + branchH / 2, bx, ly - (LEAF_FONT + PAD_V_LEAF * 2) / 2)}
                    fill="none" stroke={p.main} strokeWidth="1.3"
                    opacity="0.12" strokeLinecap="round"
                  />
                );
              })}
            </g>
          );
        })}

        {/* Root */}
        <rect
          x={rootX - rootW / 2} y={rootY - rootH / 2}
          width={rootW} height={rootH}
          rx={rootH / 2} fill="#1A1A2E"
        />
        <text x={rootX} y={rootY + ROOT_FONT * 0.35} textAnchor="middle" fill="#FFFFFF"
          fontSize={ROOT_FONT} fontWeight="600" fontFamily={FONT}>
          {data.topic}
        </text>

        {/* Branches + Leaves */}
        {data.branches.map((branch, bi) => {
          const bx = branchXs[bi];
          const p = PALETTE[branch.color];
          const isHB = hovered === `b-${bi}`;

          const bTW = textWidth(branch.topic, BRANCH_FONT, 600);
          const bW = bTW + PAD_H * 2;
          const bH = BRANCH_FONT + PAD_V_BRANCH * 2;

          return (
            <g key={bi}>
              {/* Branch */}
              <rect
                x={bx - bW / 2} y={BRANCH_Y - bH / 2}
                width={bW} height={bH} rx={bH / 2}
                fill={p.main}
                style={{
                  cursor: "pointer",
                  transition: "all 0.2s ease",
                  filter: isHB ? `drop-shadow(0 4px 12px ${p.main}44)` : "none",
                }}
                onMouseEnter={() => setHovered(`b-${bi}`)}
                onMouseLeave={() => setHovered(null)}
              />
              <text x={bx} y={BRANCH_Y + BRANCH_FONT * 0.35} textAnchor="middle"
                fill="#FFFFFF" fontSize={BRANCH_FONT} fontWeight="600"
                fontFamily={FONT} pointerEvents="none">
                {branch.topic}
              </text>

              {/* Leaves */}
              {branch.children.map((leaf, li) => {
                const ly = LEAF_START_Y + li * LEAF_GAP;
                const isHL = hovered === `l-${bi}-${li}`;

                const lTW = textWidth(leaf, LEAF_FONT, 500);
                const lW = lTW + PAD_H * 2;
                const lH = LEAF_FONT + PAD_V_LEAF * 2;

                return (
                  <g key={li}>
                    <circle cx={bx} cy={ly - lH / 2 - 4} r="2.5" fill={p.main} opacity="0.25" />
                    <rect
                      x={bx - lW / 2} y={ly - lH / 2}
                      width={lW} height={lH} rx={lH / 2}
                      fill={isHL ? p.leafHover : p.soft}
                      stroke={isHL ? p.main : p.softBorder}
                      strokeWidth={isHL ? "1.5" : "1"}
                      style={{
                        cursor: "pointer",
                        transition: "all 0.15s ease",
                      }}
                      onMouseEnter={() => setHovered(`l-${bi}-${li}`)}
                      onMouseLeave={() => setHovered(null)}
                    />
                    <text x={bx} y={ly + LEAF_FONT * 0.35} textAnchor="middle"
                      fill={isHL ? p.main : "#555"}
                      fontSize={LEAF_FONT} fontWeight={isHL ? "600" : "500"}
                      fontFamily={FONT} pointerEvents="none"
                      style={{ transition: "all 0.15s" }}>
                      {leaf}
                    </text>
                  </g>
                );
              })}
            </g>
          );
        })}
      </svg>
    </div>
  );
}

function JsonPreview({ data }) {
  const json = JSON.stringify(data, null, 2);
  return (
    <pre style={{
      background: "#FAFAF8", color: "#BBB", padding: 16,
      borderRadius: 12, fontSize: 10.5, lineHeight: 1.5,
      overflowX: "auto", border: "1px solid #F0EDE8",
      maxHeight: 220, overflowY: "auto",
      fontFamily: "'JetBrains Mono', 'Fira Code', monospace",
    }}>
      {json.split("\n").map((line, i) => (
        <div key={i}>
          <span style={{ color: "#DDD", fontSize: 9, display: "inline-block", width: 20, textAlign: "right", marginRight: 10 }}>{i + 1}</span>
          {line.includes('"topic"')
            ? <span style={{ color: "#1A1A2E" }}>{line}</span>
            : line.includes('"children"') || line.includes('"branches"')
              ? <span style={{ color: "#2BAC76" }}>{line}</span>
              : line.includes('"color"')
                ? <span style={{ color: "#6C5CE7" }}>{line}</span>
                : <span style={{ color: "#CCC" }}>{line}</span>
          }
        </div>
      ))}
    </pre>
  );
}

export default function App() {
  const [idx, setIdx] = useState(0);
  const lecture = LECTURES[idx];

  return (
    <div style={{ fontFamily: FONT, background: "#FFFFFF", minHeight: "100vh", color: "#333" }}>
      {/* Header */}
      <div style={{ padding: "26px 24px 20px", borderBottom: "1px solid #F0EDE8" }}>
        <div style={{ maxWidth: 960, margin: "0 auto" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 6 }}>
            <div style={{
              width: 34, height: 34, borderRadius: 10, background: "#1A1A2E",
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: 17, color: "#d4a574",
            }}>☕</div>
            <div>
              <div style={{
                fontSize: 9, letterSpacing: 3, textTransform: "uppercase",
                color: "#C4A882", fontWeight: 600, marginBottom: 1,
              }}>Coffee · Mapa Mental</div>
              <div style={{ fontSize: 18, color: "#1A1A2E", fontWeight: 600 }}>
                JSON Nativo — Padding Dinâmico
              </div>
            </div>
          </div>
          <p style={{ fontSize: 12, color: "#AAA", margin: 0, fontWeight: 400 }}>
            Cards se adaptam ao tamanho do texto. Padding consistente em todos os nós.
          </p>
        </div>
      </div>

      <div style={{ maxWidth: 960, margin: "0 auto", padding: "20px 24px 56px" }}>
        {/* Tabs */}
        <div style={{ display: "flex", gap: 8, marginBottom: 22, flexWrap: "wrap" }}>
          {LECTURES.map((l, i) => {
            const active = idx === i;
            return (
              <button key={i} onClick={() => setIdx(i)} style={{
                padding: "10px 18px", borderRadius: 12,
                border: active ? "1.5px solid #1A1A2E" : "1.5px solid #EEEBE6",
                background: active ? "#1A1A2E" : "#FFFFFF",
                cursor: "pointer", transition: "all 0.2s", textAlign: "left",
              }}>
                <div style={{ fontSize: 12, fontWeight: 600, color: active ? "#FFFFFF" : "#999" }}>
                  {l.label}
                </div>
                <div style={{ fontSize: 10, color: active ? "#ffffff88" : "#CCC", marginTop: 1, fontWeight: 400 }}>
                  {l.date} · {l.professor}
                </div>
              </button>
            );
          })}
        </div>

        {/* Mind Map */}
        <div style={{ borderRadius: 16, border: "1px solid #F0EDE8", overflow: "hidden" }}>
          <MindMap data={lecture.data} animKey={idx} />
        </div>

        {/* Stats */}
        <div style={{
          display: "flex", gap: 20, marginTop: 16,
          fontSize: 11, color: "#BBB", fontWeight: 500, flexWrap: "wrap",
        }}>
          <span>Consistência <b style={{ color: "#1A1A2E" }}>9/10</b></span>
          <span>Custo <b style={{ color: "#1A1A2E" }}>~$0.002</b></span>
          <span>Latência <b style={{ color: "#1A1A2E" }}>+0s</b></span>
          <span>Offline <b style={{ color: "#2BAC76" }}>Sim</b></span>
          <span>Branding <b style={{ color: "#2BAC76" }}>Total</b></span>
        </div>

        {/* JSON */}
        <div style={{ marginTop: 24 }}>
          <div style={{
            fontSize: 11, color: "#AAA", marginBottom: 8,
            display: "flex", alignItems: "center", gap: 8, fontWeight: 500,
          }}>
            <span style={{
              background: "#1A1A2E", color: "#FFFFFF", padding: "3px 10px",
              borderRadius: 6, fontSize: 9, fontWeight: 600, letterSpacing: 0.5,
            }}>JSONB</span>
            Campo <code style={{ color: "#1A1A2E", background: "#F5F3F0", padding: "2px 7px", borderRadius: 5, fontSize: 10, fontWeight: 600 }}>mind_map</code> salvo na gravação
          </div>
          <JsonPreview data={lecture.data} />
        </div>

        {/* Pipeline */}
        <div style={{ marginTop: 28, display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
          {[
            { step: "1", title: "GPT-4o-mini gera JSON", desc: "A partir do resumo. Schema fixo: 4 branches × 3 folhas × max 20 chars.", accent: "#E8453C" },
            { step: "2", title: "Backend salva JSONB", desc: "Campo mind_map na tabela gravacoes. Mesmo background task do resumo.", accent: "#2BAC76" },
            { step: "3", title: "iOS renderiza SwiftUI", desc: "Padding dinâmico, cores do branding. Texto curto = card curto. Texto longo = card longo.", accent: "#6C5CE7" },
          ].map((s, i) => (
            <div key={i} style={{
              background: "#FAFAF8", border: "1px solid #F0EDE8",
              borderRadius: 14, padding: "18px 16px",
            }}>
              <div style={{
                width: 26, height: 26, borderRadius: 13,
                background: s.accent, color: "#FFFFFF",
                display: "flex", alignItems: "center", justifyContent: "center",
                fontSize: 11, fontWeight: 700, marginBottom: 10,
              }}>{s.step}</div>
              <div style={{ fontSize: 12.5, fontWeight: 600, color: "#1A1A2E", marginBottom: 4 }}>{s.title}</div>
              <div style={{ fontSize: 11, color: "#999", lineHeight: 1.6, fontWeight: 400 }}>{s.desc}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
