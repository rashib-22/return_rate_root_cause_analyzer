
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import seaborn as sns
from sqlalchemy import create_engine, text
from pathlib import Path
import warnings
warnings.filterwarnings("ignore")

DB = dict(host="localhost", port=3306, user="root",
          password="your_password_here", database="return_analyzer")

CHARTS = Path("outputs/charts")
CHARTS.mkdir(parents=True, exist_ok=True)

BG      = "#0F1923"
PANEL   = "#1A2634"
FG      = "#E8E8E8"
ACCENT  = "#FF6B35"
PALETTE = ["#FF6B35","#004E89","#1A936F","#C84B31","#F4A261",
           "#457B9D","#E9C46A","#264653","#2A9D8F","#E76F51",
           "#A8DADC","#F1FAEE","#E63946"]

plt.rcParams.update({
    "figure.facecolor": BG, "axes.facecolor": PANEL,
    "axes.edgecolor":   "#2E3F55", "axes.labelcolor": FG,
    "text.color": FG,   "xtick.color": FG, "ytick.color": FG,
    "grid.color": "#2E3F55", "grid.alpha": 0.45,
    "font.family": "DejaVu Sans", "font.size": 11,
})

def conn():
    url = (f"mysql+pymysql://{DB['user']}:{DB['password']}"
           f"@{DB['host']}:{DB['port']}/{DB['database']}?charset=utf8mb4")
    return create_engine(url, echo=False)

def q(sql, eng):
    return pd.read_sql(text(sql), con=eng.connect())

def save(name):
    p = CHARTS / f"{name}.png"
    plt.savefig(p, dpi=150, bbox_inches="tight", facecolor=BG)
    plt.close()
    print(f"  ✓  {name}.png")

def main():
    print("="*50)
    print("  EDA — Return Rate Root Cause Analyzer")
    print("="*50)
    eng = conn()

    #CHART 1: KPI CARDS
    print("\n[1/10] KPI cards")
    kpi = q("""
        SELECT
            COUNT(DISTINCT o.order_id)                                              AS orders,
            COUNT(DISTINCT r.return_id)                                             AS returns,
            ROUND(COUNT(DISTINCT r.return_id)*100.0/COUNT(DISTINCT o.order_id),2)  AS rr,
            ROUND(COALESCE(SUM(r.total_loss),0)/1000000,2)                         AS loss_m,
            ROUND(COALESCE(SUM(r.total_loss),0)/SUM(o.total_paid)*100,2)           AS margin
        FROM orders o LEFT JOIN returns r ON o.order_id=r.order_id
    """, eng).iloc[0]

    fig, axes = plt.subplots(1, 5, figsize=(24, 4))
    fig.suptitle("Executive KPIs — Quick Commerce Return Analysis",
                 fontsize=14, fontweight="bold", color=FG, y=1.04)
    cards = [
        ("Total Orders",    f"{int(kpi.orders):,}",     "#4FC3F7"),
        ("Total Returns",   f"{int(kpi.returns):,}",    "#C84B31"),
        ("Return Rate",     f"{kpi.rr}%",               ACCENT),
        ("Total Loss",      f"₹{kpi.loss_m}M",          "#E76F51"),
        ("Margin Erosion",  f"{kpi.margin}%",           "#E9C46A"),
    ]
    for ax, (lbl, val, clr) in zip(axes, cards):
        ax.set_facecolor(clr + "20")
        for sp in ax.spines.values(): sp.set_color(clr); sp.set_linewidth(2)
        ax.text(0.5, 0.58, val, ha="center", va="center",
                fontsize=30, fontweight="bold", color=clr, transform=ax.transAxes)
        ax.text(0.5, 0.22, lbl, ha="center", va="center",
                fontsize=10, color=FG, transform=ax.transAxes)
        ax.set_xticks([]); ax.set_yticks([])
    save("01_kpi_cards")

    #CHART 2: CATEGORY RETURN RATE 
    print("[2/10] Category return rate")
    cat = q("""
        SELECT o.category,
               ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) AS rr,
               ROUND(COALESCE(SUM(r.total_loss),0)/1000,0) AS loss_k
        FROM orders o LEFT JOIN returns r ON o.order_id=r.order_id
        GROUP BY o.category ORDER BY rr DESC
    """, eng)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(18, 7))
    fig.suptitle("Return Rate & Loss by Product Category", fontsize=14, fontweight="bold")

    clrs = [PALETTE[i % len(PALETTE)] for i in range(len(cat))]
    cat_sorted = cat.sort_values("rr", ascending=True)
    bars = ax1.barh(cat_sorted["category"], cat_sorted["rr"],
                    color=clrs, edgecolor="none", height=0.62)
    ax1.set_xlabel("Return Rate (%)"); ax1.set_title("Return Rate %")
    avg = cat_sorted["rr"].mean()
    ax1.axvline(avg, color="white", ls="--", lw=1.5, alpha=0.6, label=f"Avg {avg:.1f}%")
    ax1.legend(fontsize=9)
    for bar, val in zip(bars, cat_sorted["rr"]):
        ax1.text(bar.get_width()+0.2, bar.get_y()+bar.get_height()/2,
                 f"{val:.1f}%", va="center", fontsize=9)
    ax1.grid(axis="x", alpha=0.3)

    cat_loss = cat.sort_values("loss_k", ascending=True)
    bars2 = ax2.barh(cat_loss["category"], cat_loss["loss_k"],
                     color=clrs, edgecolor="none", height=0.62)
    ax2.set_xlabel("Total Loss (₹ Thousands)"); ax2.set_title("Financial Loss (₹K)")
    for bar, val in zip(bars2, cat_loss["loss_k"]):
        ax2.text(bar.get_width()+2, bar.get_y()+bar.get_height()/2,
                 f"₹{val:.0f}K", va="center", fontsize=9)
    ax2.grid(axis="x", alpha=0.3)
    save("02_category_analysis")

    # CHART 3: DELIVERY SLOT 
    print("[3/10] Delivery slot analysis")
    slot = q("""
        SELECT o.delivery_slot,
               ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) AS rr,
               ROUND(SUM(o.sla_breach)*100.0/COUNT(o.order_id),2)  AS breach,
               ROUND(AVG(o.delivery_minutes),1) AS avg_mins,
               COUNT(o.order_id) AS orders
        FROM orders o GROUP BY o.delivery_slot ORDER BY rr DESC
    """, eng)

    fig, ax1 = plt.subplots(figsize=(14, 6))
    ax1.set_title("Delivery Slot: Return Rate vs SLA Breach Rate",
                  fontsize=14, fontweight="bold")
    x = range(len(slot))
    slot_clrs = ["#C84B31" if r>26 else "#E76F51" if r>20 else
                 "#F4A261" if r>14 else "#1A936F" for r in slot["rr"]]
    bars = ax1.bar(x, slot["rr"], color=slot_clrs, alpha=0.85, width=0.5, label="Return Rate %")
    ax1.set_xticks(x)
    ax1.set_xticklabels(slot["delivery_slot"], rotation=12, ha="right", fontsize=9)
    ax1.set_ylabel("Return Rate (%)", color=ACCENT)
    for bar, val in zip(bars, slot["rr"]):
        ax1.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.3,
                 f"{val:.1f}%", ha="center", fontsize=10, fontweight="bold")

    ax2 = ax1.twinx()
    ax2.plot(x, slot["breach"], color="#4FC3F7", marker="D",
             lw=2.5, ms=9, label="SLA Breach %")
    ax2.set_ylabel("SLA Breach Rate (%)", color="#4FC3F7")
    ax2.tick_params(axis="y", colors="#4FC3F7")

    h1,l1 = ax1.get_legend_handles_labels()
    h2,l2 = ax2.get_legend_handles_labels()
    ax1.legend(h1+h2, l1+l2, loc="upper right", fontsize=9)
    ax1.grid(axis="y", alpha=0.3)
    save("03_slot_analysis")

    # CHART 4: CUSTOMER SEGMENT 
    print("[4/10] Customer segment")
    seg_order = ["New","Growing","Loyal","Champion"]
    seg = q("""
        SELECT o.customer_segment,
               COUNT(DISTINCT o.customer_id) AS customers,
               ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) AS rr,
               ROUND(COALESCE(SUM(r.total_loss),0)/1000,0) AS loss_k
        FROM orders o LEFT JOIN returns r ON o.order_id=r.order_id
        GROUP BY o.customer_segment
    """, eng)
    seg["customer_segment"] = pd.Categorical(seg["customer_segment"],
                                              categories=seg_order, ordered=True)
    seg = seg.sort_values("customer_segment")

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 6))
    fig.suptitle("Customer Tenure Segment Analysis", fontsize=14, fontweight="bold")
    seg_clrs = ["#C84B31","#E76F51","#F4A261","#1A936F"]
    bars = ax1.bar(seg["customer_segment"], seg["rr"],
                   color=seg_clrs, edgecolor="none", width=0.52)
    ax1.set_title("Return Rate by Segment"); ax1.set_ylabel("Return Rate (%)")
    for bar, val in zip(bars, seg["rr"]):
        ax1.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.2,
                 f"{val:.1f}%", ha="center", fontsize=13, fontweight="bold")
    ax1.set_xticklabels(seg["customer_segment"], rotation=10, ha="right")
    ax1.grid(axis="y", alpha=0.3)

    bars2 = ax2.bar(seg["customer_segment"], seg["loss_k"],
                    color=seg_clrs, edgecolor="none", width=0.52)
    ax2.set_title("Total Loss by Segment (₹K)"); ax2.set_ylabel("Loss (₹K)")
    for bar, val in zip(bars2, seg["loss_k"]):
        ax2.text(bar.get_x()+bar.get_width()/2, bar.get_height()+10,
                 f"₹{val:.0f}K", ha="center", fontsize=11, fontweight="bold")
    ax2.set_xticklabels(seg["customer_segment"], rotation=10, ha="right")
    ax2.grid(axis="y", alpha=0.3)
    save("04_segment_analysis")

    # CHART 5: CITY × CATEGORY HEATMAP 
    print("[5/10] City × Category heatmap")
    cc = q("""
        SELECT o.city, o.category,
               ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) AS rr
        FROM orders o GROUP BY o.city, o.category
    """, eng)
    pivot = cc.pivot(index="city", columns="category", values="rr").fillna(0)

    fig, ax = plt.subplots(figsize=(18, 7))
    sns.heatmap(pivot, ax=ax, cmap="RdYlGn_r", annot=True, fmt=".1f",
                linewidths=0.5, linecolor="#0F1923",
                cbar_kws={"label":"Return Rate %","shrink":0.7},
                annot_kws={"size":9, "color":"white"})
    ax.set_title("Return Rate Heatmap: City × Category  (darker = worse)",
                 fontsize=14, fontweight="bold")
    ax.set_xlabel(""); ax.set_ylabel(""); ax.tick_params(axis="x", rotation=28)
    save("05_city_category_heatmap")

    #  CHART 6: RETURN REASONS 
    print("[6/10] Return reasons")
    rsn = q("""
        SELECT return_reason, return_reason_group,
               COUNT(*) AS n,
               ROUND(SUM(total_loss)/1000,1) AS loss_k
        FROM returns GROUP BY return_reason, return_reason_group
        ORDER BY n DESC
    """, eng)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(18, 7))
    fig.suptitle("Return Reasons: Volume & Financial Loss", fontsize=14, fontweight="bold")
    rsn_s = rsn.sort_values("n", ascending=True)
    group_clrs = {"Logistics":"#C84B31","Quality":"#E9C46A","Customer":"#4FC3F7"}
    clrs_rsn = [group_clrs.get(g,"#999") for g in rsn_s["return_reason_group"]]
    ax1.barh(rsn_s["return_reason"], rsn_s["n"], color=clrs_rsn, edgecolor="none")
    ax1.set_title("Volume (# Returns)"); ax1.set_xlabel("Count")
    for i, val in enumerate(rsn_s["n"]):
        ax1.text(val+20, i, f"{val:,}", va="center", fontsize=9)
    ax1.grid(axis="x", alpha=0.3)
    patches = [mpatches.Patch(color=c, label=l) for l,c in group_clrs.items()]
    ax1.legend(handles=patches, fontsize=9, title="Reason Group")

    rsn_l = rsn.sort_values("loss_k", ascending=True)
    ax2.barh(rsn_l["return_reason"], rsn_l["loss_k"],
             color=[group_clrs.get(g,"#999") for g in rsn_l["return_reason_group"]],
             edgecolor="none")
    ax2.set_title("Financial Loss (₹ Thousands)"); ax2.set_xlabel("Loss (₹K)")
    for i, val in enumerate(rsn_l["loss_k"]):
        ax2.text(val+1, i, f"₹{val:.0f}K", va="center", fontsize=9)
    ax2.grid(axis="x", alpha=0.3)
    save("06_return_reasons")

    #  CHART 7: MONTHLY TREND 
    print("[7/10] Monthly trend")
    mon = q("""
        SELECT o.order_month,
               COUNT(o.order_id) AS orders,
               ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) AS rr,
               ROUND(COALESCE(SUM(r.total_loss),0)/1000,0) AS loss_k
        FROM orders o LEFT JOIN returns r ON o.order_id=r.order_id
        GROUP BY o.order_month ORDER BY o.order_month
    """, eng)

    fig, ax1 = plt.subplots(figsize=(16, 5))
    ax1.set_title("Monthly Return Rate Trend (Jul 2022 – Jun 2024)",
                  fontsize=14, fontweight="bold")
    x = range(len(mon))
    ax1.fill_between(x, mon["rr"], alpha=0.22, color=ACCENT)
    ax1.plot(x, mon["rr"], color=ACCENT, lw=2.5, marker="o", ms=6, label="Return Rate %")
    ax1.set_xticks(x)
    ax1.set_xticklabels(mon["order_month"], rotation=35, ha="right", fontsize=8)
    ax1.set_ylabel("Return Rate (%)", color=ACCENT)
    ax1.grid(alpha=0.3)

    ax2 = ax1.twinx()
    ax2.bar(x, mon["orders"], width=0.65, alpha=0.22, color="#4FC3F7", label="Orders")
    ax2.set_ylabel("Order Volume", color="#4FC3F7")
    ax2.tick_params(axis="y", colors="#4FC3F7")
    h1,l1 = ax1.get_legend_handles_labels()
    h2,l2 = ax2.get_legend_handles_labels()
    ax1.legend(h1+h2, l1+l2, loc="upper left", fontsize=9)
    save("07_monthly_trend")

    #  CHART 8: SLA BREACH IMPACT 
    print("[8/10] SLA breach impact")
    sla = q("""
        SELECT CASE sla_breach WHEN 1 THEN 'SLA Breached' ELSE 'SLA Met' END AS status,
               COUNT(order_id) AS orders,
               ROUND(SUM(is_returned)*100.0/COUNT(order_id),2) AS rr,
               ROUND(AVG(delivery_minutes),1) AS avg_mins
        FROM orders GROUP BY sla_breach ORDER BY rr DESC
    """, eng)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 6))
    fig.suptitle("SLA Breach Impact on Returns", fontsize=14, fontweight="bold")
    sla_clrs = ["#C84B31","#1A936F"]
    for ax, col, title, suffix in [
        (ax1, "rr",       "Return Rate (%)",             "%"),
        (ax2, "avg_mins", "Avg Delivery Time (minutes)", " min"),
    ]:
        bars = ax.bar(sla["status"], sla[col], color=sla_clrs, edgecolor="none", width=0.45)
        ax.set_title(title)
        for bar, val in zip(bars, sla[col]):
            ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.3,
                    f"{val:.1f}{suffix}", ha="center", fontsize=13, fontweight="bold")
        ax.grid(axis="y", alpha=0.3)
    save("08_sla_impact")

    #  CHART 9: BRAND TIER 
    print("[9/10] Brand tier analysis")
    brand = q("""
        SELECT o.brand_tier,
               ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) AS rr,
               ROUND(AVG(o.mrp),0) AS avg_mrp,
               ROUND(COALESCE(SUM(r.total_loss),0)/1000,0) AS loss_k
        FROM orders o LEFT JOIN returns r ON o.order_id=r.order_id
        GROUP BY o.brand_tier ORDER BY rr DESC
    """, eng)

    fig, axes = plt.subplots(1, 3, figsize=(16, 5))
    fig.suptitle("Brand Tier Analysis", fontsize=14, fontweight="bold")
    tier_clrs = ["#C84B31","#F4A261","#1A936F"]
    for ax, col, title, pfx in [
        (axes[0], "rr",      "Return Rate (%)",   ""),
        (axes[1], "avg_mrp", "Avg MRP (₹)",       "₹"),
        (axes[2], "loss_k",  "Total Loss (₹K)",   "₹"),
    ]:
        bars = ax.bar(brand["brand_tier"], brand[col], color=tier_clrs,
                      edgecolor="none", width=0.5)
        ax.set_title(title)
        for bar, val in zip(bars, brand[col]):
            ax.text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.5,
                    f"{pfx}{val:.0f}", ha="center", fontsize=12, fontweight="bold")
        ax.grid(axis="y", alpha=0.3)
    save("09_brand_tier")

    #  CHART 10: TOP RISK SKUs 
    print("[10/10] Top risk SKUs")
    sku = q("""
        SELECT o.sku_id, p.product_name, o.category,
               ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) AS rr,
               ROUND(COALESCE(SUM(r.total_loss),0)/1000,1) AS loss_k
        FROM orders o JOIN products p ON o.sku_id=p.sku_id
        LEFT JOIN returns r ON o.order_id=r.order_id
        GROUP BY o.sku_id, p.product_name, o.category
        HAVING COUNT(o.order_id)>=40 AND SUM(o.is_returned)*100.0/COUNT(o.order_id)>20
        ORDER BY loss_k DESC LIMIT 15
    """, eng)

    fig, ax = plt.subplots(figsize=(14, 8))
    ax.set_title(f"Top {len(sku)} High-Risk SKUs  (min 40 orders, >20% return rate)",
                 fontsize=13, fontweight="bold")
    clrs_sku = plt.cm.RdYlGn_r([i/max(len(sku)-1,1) for i in range(len(sku))])
    labels = [f"{r.product_name[:30]}  ({r.category[:18]})" for _,r in sku.iterrows()]
    bars = ax.barh(labels, sku["loss_k"], color=clrs_sku, edgecolor="none")
    ax.set_xlabel("Total Loss (₹ Thousands)")
    for bar, rate in zip(bars, sku["rr"]):
        ax.text(bar.get_width()+0.3, bar.get_y()+bar.get_height()/2,
                f"{rate:.1f}% return", va="center", fontsize=8)
    ax.grid(axis="x", alpha=0.3)
    save("10_top_risk_skus")

    print(f"\n✅  All 10 charts saved → {CHARTS}/")

if __name__ == "__main__":
    main()
