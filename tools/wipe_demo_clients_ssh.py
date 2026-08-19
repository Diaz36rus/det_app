# -*- coding: utf-8 -*-
"""Wipe demo company orders + clients via SSH/psql (no API deploy needed)."""
import subprocess
import sys

HOST = "135.106.186.90"
USER = "root"
KEY = __import__("os").path.expanduser("~/.ssh/id_ed25519")
SSH = r"C:\Program Files\Git\usr\bin\ssh.exe"

SQL = r"""
DO $$
DECLARE
  cid int;
  oids int[];
BEGIN
  SELECT id INTO cid FROM companies WHERE slug = 'demo';
  IF cid IS NULL THEN
    RAISE NOTICE 'demo company missing';
    RETURN;
  END IF;

  SELECT COALESCE(array_agg(id), ARRAY[]::int[]) INTO oids
  FROM crm_orders WHERE company_id = cid;

  IF array_length(oids, 1) IS NOT NULL THEN
    DELETE FROM cash_payments WHERE crm_order_id = ANY(oids);
    UPDATE cash_flows SET order_id = NULL WHERE order_id = ANY(oids);
    UPDATE crm_inventory_moves SET order_id = NULL WHERE order_id = ANY(oids);
    DELETE FROM crm_orders WHERE company_id = cid;
  END IF;

  DELETE FROM crm_cars WHERE company_id = cid;
  DELETE FROM crm_clients WHERE company_id = cid;

  RAISE NOTICE 'wiped demo company_id=% orders=%', cid, COALESCE(array_length(oids,1),0);
END $$;

SELECT
  (SELECT count(*) FROM crm_orders WHERE company_id = (SELECT id FROM companies WHERE slug='demo')) AS orders,
  (SELECT count(*) FROM crm_clients WHERE company_id = (SELECT id FROM companies WHERE slug='demo')) AS clients,
  (SELECT count(*) FROM crm_cars WHERE company_id = (SELECT id FROM companies WHERE slug='demo')) AS cars,
  (SELECT count(*) FROM crm_services WHERE company_id = (SELECT id FROM companies WHERE slug='demo') AND is_active) AS services;
"""


def main():
    remote = (
        "cd /opt/det-app && docker compose exec -T db "
        "psql -U detapp -d detapp -v ON_ERROR_STOP=1"
    )
    cmd = [
        SSH,
        "-i",
        KEY,
        "-o",
        "BatchMode=yes",
        "-o",
        "StrictHostKeyChecking=accept-new",
        f"{USER}@{HOST}",
        remote,
    ]
    print("running remote wipe…", flush=True)
    p = subprocess.run(cmd, input=SQL.encode("utf-8"), capture_output=True)
    sys.stdout.buffer.write(p.stdout)
    sys.stderr.buffer.write(p.stderr)
    if p.returncode != 0:
        raise SystemExit(p.returncode)
    print("done", flush=True)


if __name__ == "__main__":
    main()
