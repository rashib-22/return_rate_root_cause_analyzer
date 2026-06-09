"""
FILE : 04_ml_classification.py
RUN  : python 04_ml_classification.py
NEEDS: pip install pandas sqlalchemy pymysql scikit-learn xgboost imbalanced-learn matplotlib seaborn joblib

Trains XGBoost to predict return probability → scores all 80K orders → exports risk CSVs.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from sqlalchemy import create_engine, text
from pathlib import Path
import warnings, joblib
warnings.filterwarnings("ignore")

from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import (classification_report, confusion_matrix,
                             roc_auc_score, roc_curve,
                             average_precision_score, precision_recall_curve)
from xgboost import XGBClassifier
from imblearn.over_sampling import SMOTE

# ── CONFIG ─────────────────────────────────────────────────────
DB = dict(host="localhost", port=3306, user="root",
          password="your_password_here", database="return_analyzer")

CHARTS = Path("outputs/charts")
MODELS = Path("outputs/models")
OUT    = Path("outputs")
for d in [CHARTS, MODELS, OUT]: d.mkdir(parents=True, exist_ok=True)

BG="0F1923"; PANEL="#1A2634"; FG="#E8E8E8"; ACCENT="#FF6B35"
PALETTE=["#FF6B35","#004E89","#1A936F","#C84B31","#F4A261","#457B9D","#E9C46A","#264653"]
plt.rcParams.update({
    "figure.facecolor":"#"+BG,"axes.facecolor":PANEL,
    "axes.edgecolor":"#2E3F55","axes.labelcolor":FG,
    "text.color":FG,"xtick.color":FG,"ytick.color":FG,
    "grid.color":"#2E3F55","grid.alpha":0.45,
    "font.family":"DejaVu Sans","font.size":11,
})

def save(name):
    p = CHARTS/f"{name}.png"
    plt.savefig(p,dpi=150,bbox_inches="tight",facecolor="#"+BG)
    plt.close(); print(f"  ✓  {name}.png")

def conn():
    url=(f"mysql+pymysql://{DB['user']}:{DB['password']}"
         f"@{DB['host']}:{DB['port']}/{DB['database']}?charset=utf8mb4")
    return create_engine(url,echo=False)

# ── STEP 1: LOAD ────────────────────────────────────────────────
def load(eng):
    print("\n[1/6] Loading orders from MySQL...")
    df = pd.read_sql(text("SELECT * FROM orders"), con=eng.connect())
    print(f"  {len(df):,} rows  |  return rate {df.is_returned.mean()*100:.1f}%")
    return df

# ── STEP 2: FEATURE ENGINEERING ────────────────────────────────
def features(df):
    print("\n[2/6] Feature engineering...")
    slot_risk = {
        "Early Morning (6–9 AM)":1,"Morning (9 AM–12 PM)":2,
        "Afternoon (12–3 PM)":3,"Evening (3–6 PM)":4,
        "Prime Evening (6–9 PM)":5,"Night (9 PM–12 AM)":2,
    }
    df["slot_risk"]          = df["delivery_slot"].map(slot_risk).fillna(3)
    df["perishable_x_slot"]  = df["is_perishable"] * (df["slot_risk"]>=4).astype(int)
    df["new_cust_perishable"]= ((df["customer_tenure_days"]<30)&(df["is_perishable"]==1)).astype(int)
    df["high_discount"]      = (df["discount_pct"]>25).astype(int)
    df["log_tenure"]         = np.log1p(df["customer_tenure_days"])
    df["delay_ratio"]        = df["delivery_minutes"]/20.0
    df["value_per_unit"]     = df["total_paid"]/df["quantity"].clip(lower=1)

    cat_cols=["category","sub_category","city","delivery_slot",
              "customer_segment","brand_tier","order_dow","payment_method","order_source"]
    encs={}
    for c in cat_cols:
        le=LabelEncoder()
        df[c+"_enc"]=le.fit_transform(df[c].astype(str))
        encs[c]=le
    joblib.dump(encs, MODELS/"encoders.pkl")

    FEATS=[
        "category_enc","sub_category_enc","city_enc","delivery_slot_enc",
        "customer_segment_enc","brand_tier_enc","order_dow_enc",
        "payment_method_enc","order_source_enc",
        "quantity","mrp","discount_amount","discount_pct","total_paid",
        "sla_breach","delivery_minutes","customer_tenure_days","is_perishable",
        "slot_risk","perishable_x_slot","new_cust_perishable",
        "high_discount","log_tenure","delay_ratio","value_per_unit",
    ]
    print(f"  {len(FEATS)} features ready")
    return df, FEATS, encs

# ── STEP 3: SPLIT + SMOTE ──────────────────────────────────────
def split(df, feats):
    print("\n[3/6] Train/test split + SMOTE balancing...")
    X, y = df[feats], df["is_returned"]
    Xtr,Xte,ytr,yte = train_test_split(X,y,test_size=0.2,random_state=42,stratify=y)
    print(f"  Train {len(Xtr):,}  |  Test {len(Xte):,}")
    Xtr_r,ytr_r = SMOTE(random_state=42).fit_resample(Xtr,ytr)
    print(f"  After SMOTE: {pd.Series(ytr_r).value_counts().to_dict()}")
    return Xtr_r,Xte,ytr_r,yte

# ── STEP 4: TRAIN XGBOOST ──────────────────────────────────────
def train(Xtr,Xte,ytr,yte):
    print("\n[4/6] Training XGBoost...")
    m = XGBClassifier(
        n_estimators=350, max_depth=6, learning_rate=0.05,
        subsample=0.8, colsample_bytree=0.8, min_child_weight=3,
        eval_metric="logloss", use_label_encoder=False,
        random_state=42, n_jobs=-1, verbosity=0,
    )
    m.fit(Xtr,ytr,eval_set=[(Xte,yte)],verbose=False)
    yp  = m.predict(Xte)
    ypr = m.predict_proba(Xte)[:,1]
    print("\n  ── Classification Report ──")
    print(classification_report(yte,yp,target_names=["No Return","Return"]))
    auc = roc_auc_score(yte,ypr)
    ap  = average_precision_score(yte,ypr)
    print(f"  ROC-AUC: {auc:.4f}  |  Avg Precision: {ap:.4f}")
    joblib.dump(m, MODELS/"xgb_return_model.pkl")
    print(f"  Model saved → {MODELS}/xgb_return_model.pkl")
    return m, yp, ypr, auc, ap

# ── STEP 5: CHARTS ─────────────────────────────────────────────
def charts(m, feats, yte, yp, ypr, auc, ap):
    print("\n[5/6] Generating model charts...")

    # ROC + PR
    fig,(ax1,ax2)=plt.subplots(1,2,figsize=(14,6))
    fig.suptitle("XGBoost — Return Prediction Model Performance",fontsize=14,fontweight="bold")
    fpr,tpr,_=roc_curve(yte,ypr)
    ax1.plot(fpr,tpr,color=ACCENT,lw=2.5,label=f"XGBoost AUC={auc:.3f}")
    ax1.plot([0,1],[0,1],color="#555",ls="--")
    ax1.fill_between(fpr,tpr,alpha=0.15,color=ACCENT)
    ax1.set_xlabel("False Positive Rate"); ax1.set_ylabel("True Positive Rate")
    ax1.set_title("ROC Curve"); ax1.legend(fontsize=11); ax1.grid(alpha=0.3)
    prec,rec,_=precision_recall_curve(yte,ypr)
    ax2.plot(rec,prec,color="#1A936F",lw=2.5,label=f"AP={ap:.3f}")
    ax2.fill_between(rec,prec,alpha=0.15,color="#1A936F")
    ax2.set_xlabel("Recall"); ax2.set_ylabel("Precision")
    ax2.set_title("Precision-Recall Curve"); ax2.legend(fontsize=11); ax2.grid(alpha=0.3)
    save("11_model_performance")

    # Confusion matrix
    fig,ax=plt.subplots(figsize=(7,6))
    cm=confusion_matrix(yte,yp)
    sns.heatmap(cm,annot=True,fmt="d",cmap="Blues",ax=ax,
                xticklabels=["Pred No Return","Pred Return"],
                yticklabels=["Act No Return","Act Return"],
                annot_kws={"size":16},linewidths=1)
    ax.set_title("Confusion Matrix — XGBoost",fontsize=13,fontweight="bold")
    save("12_confusion_matrix")

    # Feature importance
    imp=pd.DataFrame({"feature":feats,"imp":m.feature_importances_})
    imp=imp.sort_values("imp",ascending=True).tail(15)
    fig,ax=plt.subplots(figsize=(12,7))
    clrs=plt.cm.RdYlGn(np.linspace(0.2,0.9,len(imp)))
    bars=ax.barh(imp["feature"],imp["imp"],color=clrs,edgecolor="none")
    ax.set_title("XGBoost Feature Importance — Top 15 Return Drivers",
                 fontsize=13,fontweight="bold")
    ax.set_xlabel("Importance Score")
    for bar,val in zip(bars,imp["imp"]):
        ax.text(bar.get_width()+0.0005,bar.get_y()+bar.get_height()/2,
                f"{val:.4f}",va="center",fontsize=9)
    ax.grid(axis="x",alpha=0.3)
    save("13_feature_importance")

# ── STEP 6: SCORE + EXPORT ─────────────────────────────────────
def score(df, m, feats):
    print("\n[6/6] Scoring all orders & exporting CSVs...")
    df["pred_return_prob"] = m.predict_proba(df[feats])[:,1]
    df["risk_tier"] = pd.cut(df["pred_return_prob"],
                              bins=[0,0.15,0.25,0.40,1.0],
                              labels=["Low","Medium","High","Critical"])

    # SKU risk
    sku = df.groupby("sku_id").agg(
        orders=("order_id","count"),
        actual_returns=("is_returned","sum"),
        return_rate_pct=("is_returned","mean"),
        avg_pred_prob=("pred_return_prob","mean"),
    ).reset_index()
    sku["return_rate_pct"] = (sku["return_rate_pct"]*100).round(2)
    sku["avg_pred_prob"]   = sku["avg_pred_prob"].round(4)
    sku.sort_values("avg_pred_prob",ascending=False).to_csv(OUT/"sku_risk_scores.csv",index=False)

    # City risk
    city = df.groupby("city").agg(
        orders=("order_id","count"),
        returns=("is_returned","sum"),
        return_rate_pct=("is_returned","mean"),
        avg_pred_prob=("pred_return_prob","mean"),
    ).reset_index()
    city["return_rate_pct"]=(city["return_rate_pct"]*100).round(2)
    city.to_csv(OUT/"city_risk_scores.csv",index=False)

    # Slot risk
    slot = df.groupby("delivery_slot").agg(
        orders=("order_id","count"),
        returns=("is_returned","sum"),
        return_rate_pct=("is_returned","mean"),
        avg_pred_prob=("pred_return_prob","mean"),
    ).reset_index()
    slot["return_rate_pct"]=(slot["return_rate_pct"]*100).round(2)
    slot.to_csv(OUT/"slot_risk_scores.csv",index=False)

    # Full scored file
    df.to_csv(OUT/"orders_scored.csv",index=False)

    # Risk tier chart
    tier_c=df["risk_tier"].value_counts().reindex(["Low","Medium","High","Critical"])
    tier_clrs=["#1A936F","#F4A261","#E76F51","#C84B31"]
    fig,ax=plt.subplots(figsize=(10,5))
    bars=ax.bar(tier_c.index,tier_c.values,color=tier_clrs,edgecolor="none",width=0.5)
    ax.set_title("Order Distribution by Return Risk Tier\n(XGBoost ML Predictions)",
                 fontsize=13,fontweight="bold")
    ax.set_ylabel("Number of Orders")
    for bar,(_,cnt) in zip(bars,tier_c.items()):
        ax.text(bar.get_x()+bar.get_width()/2,bar.get_height()+100,
                f"{cnt:,}\n({cnt/len(df)*100:.1f}%)",ha="center",
                fontsize=10,fontweight="bold")
    ax.grid(axis="y",alpha=0.3)
    save("14_risk_tier_distribution")

    print(f"  ✓  sku_risk_scores.csv   ({len(sku)} SKUs)")
    print(f"  ✓  city_risk_scores.csv  ({len(city)} cities)")
    print(f"  ✓  slot_risk_scores.csv  ({len(slot)} slots)")
    print(f"  ✓  orders_scored.csv     ({len(df):,} orders with risk score)")

# ── MAIN ────────────────────────────────────────────────────────
def main():
    print("="*50)
    print("  ML Pipeline — Return Rate Predictor")
    print("="*50)
    eng  = conn()
    df   = load(eng)
    df, feats, encs = features(df)
    Xtr,Xte,ytr,yte = split(df,feats)
    m,yp,ypr,auc,ap = train(Xtr,Xte,ytr,yte)
    charts(m,feats,yte,yp,ypr,auc,ap)
    score(df,m,feats)
    print("\n"+"="*50)
    print("  ✅  ML PIPELINE COMPLETE")
    print("="*50)
    print(f"\n  ROC-AUC:       {auc:.4f}")
    print(f"  Avg Precision: {ap:.4f}")
    print(f"  Outputs → {OUT}/")

if __name__=="__main__":
    main()
