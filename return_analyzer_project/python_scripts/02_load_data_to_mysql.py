

import pandas as pd
from sqlalchemy import create_engine, text
from pathlib import Path
import time
from urllib.parse import quote_plus

DB_CONFIG = {
    "host"    : "127.0.0.1",
    "port"    : 3306,
    "user"    : "root",
    "password": "aadhya@2202",   
    "database": "return_analyzer",
}
DATA_DIR = Path("data")

def engine():
    password = quote_plus(DB_CONFIG['password'])

    url = url = (f"mysql+pymysql://{DB_CONFIG['user']}:{password}"
           f"@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}"
           f"?charset=utf8mb4")
    return create_engine(url, echo=False)

def load(eng, csv_file, table, parse_dates=None):
    df = pd.read_csv(DATA_DIR / csv_file, parse_dates=parse_dates or [])
    t0 = time.time()
    df.to_sql(table, con=eng, if_exists="append", index=False,
              chunksize=2000, method="multi")
    print(f"  ✓  {table:<22} {len(df):>7,} rows  ({time.time()-t0:.1f}s)")

def main():
    print("=" * 48)
    print("  MySQL Data Loader — Return Analyzer")
    print("=" * 48)
    eng = engine()
    with eng.connect() as c:
        db = c.execute(text("SELECT DATABASE()")).fetchone()[0]
        print(f"\n  Connected → database: {db}\n")

    # Load order matters — products & customers before orders, orders before returns
    load(eng, "products.csv",       "products",       parse_dates=[])
    load(eng, "customers.csv",      "customers",      parse_dates=["join_date"])
    load(eng, "delivery_slots.csv", "delivery_slots", parse_dates=[])
    load(eng, "orders.csv",         "orders",         parse_dates=["order_date"])
    load(eng, "returns.csv",        "returns",        parse_dates=["return_date"])

    print("\n  Row count check:")
    with eng.connect() as c:
        for t in ["products","customers","delivery_slots","orders","returns"]:
            n = c.execute(text(f"SELECT COUNT(*) FROM {t}")).fetchone()[0]
            print(f"    {t:<22} {n:>7,} rows")
    print("\n   All data loaded successfully!\n")

if __name__ == "__main__":
    main()
