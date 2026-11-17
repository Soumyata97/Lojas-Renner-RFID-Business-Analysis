-- =====================================================================
-- Lojas Renner — RFID Inventory Transformation: Independent BA Case Study
-- 01_conceptual_model_ddl.sql  (v1.0, 17 Nov 2026, Soumyata Shakya)
--
-- ILLUSTRATIVE ONLY. Physical sketch of the analyst-proposed conceptual
-- model in 18_Data_Dictionary.xlsx. It is NOT Lojas Renner's database
-- schema. Syntax checked in SQLite; types are indicative (ANSI-style).
-- =====================================================================

CREATE TABLE product (
  product_id    VARCHAR(20)  PRIMARY KEY,
  product_name  VARCHAR(120) NOT NULL,
  category      VARCHAR(40)  NOT NULL
);

CREATE TABLE sku (
  sku_id        VARCHAR(20)  PRIMARY KEY,
  product_id    VARCHAR(20)  NOT NULL REFERENCES product(product_id),
  size          VARCHAR(10)  NOT NULL,
  colour        VARCHAR(30)  NOT NULL,
  unit_cost     DECIMAL(10,2) NOT NULL
);

CREATE TABLE supplier (
  supplier_id   VARCHAR(20)  PRIMARY KEY,
  supplier_name VARCHAR(120) NOT NULL
);

CREATE TABLE store (
  store_id      VARCHAR(10)  PRIMARY KEY,
  store_name    VARCHAR(80)  NOT NULL,
  last_sync_at  TIMESTAMP                                     -- BRULE-016 staleness check
);

CREATE TABLE location (
  location_id         VARCHAR(20) PRIMARY KEY,
  store_id            VARCHAR(10) NOT NULL REFERENCES store(store_id),
  zone_type           VARCHAR(20) NOT NULL CHECK (zone_type IN ('Receiving','Back room','Sales floor','Fitting room')),
  is_mandatory_count  BOOLEAN     NOT NULL DEFAULT 1           -- BRULE-007
);

CREATE TABLE app_user (
  user_id        VARCHAR(20) PRIMARY KEY,
  role           VARCHAR(30) NOT NULL,
  home_store_id  VARCHAR(10) REFERENCES store(store_id)
);

CREATE TABLE item (
  item_id          BIGINT      PRIMARY KEY,
  sku_id           VARCHAR(20) NOT NULL REFERENCES sku(sku_id),  -- BRULE-002 exactly one SKU
  supplier_id      VARCHAR(20) REFERENCES supplier(supplier_id),
  store_id         VARCHAR(10) REFERENCES store(store_id),
  location_id      VARCHAR(20) REFERENCES location(location_id),
  status           VARCHAR(15) NOT NULL CHECK (status IN ('In stock','In transit','Sold','Quarantined','Damaged')),
  security_status  VARCHAR(12) NOT NULL CHECK (security_status IN ('Active','Deactivated')),
  last_read_at     TIMESTAMP
);

CREATE TABLE rfid_tag (
  tag_id         VARCHAR(32) PRIMARY KEY,                        -- BRULE-001 unique EPC
  item_id        BIGINT      REFERENCES item(item_id),
  tag_status     VARCHAR(10) NOT NULL CHECK (tag_status IN ('Active','Retired')),
  associated_at  TIMESTAMP   NOT NULL,
  source         VARCHAR(10) NOT NULL CHECK (source IN ('Origin','In-store'))
);
-- One active tag per item (NFR-023 / DQ-01)
CREATE UNIQUE INDEX ux_one_active_tag_per_item ON rfid_tag(item_id) WHERE tag_status = 'Active';

CREATE TABLE shipment (
  shipment_id     VARCHAR(20) PRIMARY KEY,
  store_id        VARCHAR(10) NOT NULL REFERENCES store(store_id),
  supplier_id     VARCHAR(20) REFERENCES supplier(supplier_id),
  expected_items  INTEGER     NOT NULL,
  status          VARCHAR(12) NOT NULL CHECK (status IN ('Expected','Receiving','Confirmed','Unplanned'))
);

CREATE TABLE stock_count (
  count_id      BIGINT      PRIMARY KEY,
  store_id      VARCHAR(10) NOT NULL REFERENCES store(store_id),
  count_type    VARCHAR(6)  NOT NULL CHECK (count_type IN ('Full','Cycle')),
  created_by    VARCHAR(20) NOT NULL REFERENCES app_user(user_id),
  started_at    TIMESTAMP,
  closed_at     TIMESTAMP,
  close_reason  VARCHAR(200)
);

CREATE TABLE read_event (
  read_id      BIGINT      PRIMARY KEY,
  tag_id       VARCHAR(32) NOT NULL,                             -- unknown tags kept (BRULE-004), so no FK
  read_mode    VARCHAR(12) NOT NULL,
  device_id    VARCHAR(20) NOT NULL,
  user_id      VARCHAR(20) REFERENCES app_user(user_id),
  location_id  VARCHAR(20) NOT NULL REFERENCES location(location_id),
  count_id     BIGINT      REFERENCES stock_count(count_id),
  read_at      TIMESTAMP   NOT NULL
);

CREATE TABLE stock_movement (
  movement_id       BIGINT      PRIMARY KEY,
  item_id           BIGINT      NOT NULL REFERENCES item(item_id),
  movement_type     VARCHAR(15) NOT NULL,
  from_location_id  VARCHAR(20) REFERENCES location(location_id),
  to_location_id    VARCHAR(20) REFERENCES location(location_id),
  shipment_id       VARCHAR(20) REFERENCES shipment(shipment_id),
  moved_at          TIMESTAMP   NOT NULL
);

CREATE TABLE inventory_balance (                                  -- derived; could be a view
  store_id          VARCHAR(10) NOT NULL REFERENCES store(store_id),
  location_id       VARCHAR(20) NOT NULL REFERENCES location(location_id),
  sku_id            VARCHAR(20) NOT NULL REFERENCES sku(sku_id),
  qty_on_hand       INTEGER     NOT NULL,
  presentation_min  INTEGER,
  PRIMARY KEY (store_id, location_id, sku_id)
);

CREATE TABLE inventory_discrepancy (
  discrepancy_id    BIGINT      PRIMARY KEY,
  count_id          BIGINT      NOT NULL REFERENCES stock_count(count_id),
  sku_id            VARCHAR(20) NOT NULL REFERENCES sku(sku_id),
  location_id       VARCHAR(20) NOT NULL REFERENCES location(location_id),
  system_qty        INTEGER     NOT NULL,
  counted_qty       INTEGER     NOT NULL,
  variance_qty      INTEGER     NOT NULL,                        -- counted - system (BRULE-008)
  beyond_tolerance  BOOLEAN     NOT NULL,
  status            VARCHAR(10) NOT NULL,
  resolved_at       TIMESTAMP,
  CHECK (variance_qty = counted_qty - system_qty)
);

CREATE TABLE reason_code (
  reason_code  VARCHAR(10) PRIMARY KEY,
  description  VARCHAR(80) NOT NULL
);

CREATE TABLE stock_adjustment (
  adjustment_id   BIGINT        PRIMARY KEY,
  discrepancy_id  BIGINT        REFERENCES inventory_discrepancy(discrepancy_id),
  reason_code     VARCHAR(10)   NOT NULL REFERENCES reason_code(reason_code),   -- BRULE-011
  qty             INTEGER       NOT NULL,
  value           DECIMAL(12,2) NOT NULL,
  proposed_by     VARCHAR(20)   NOT NULL REFERENCES app_user(user_id),
  approved_by     VARCHAR(20)   REFERENCES app_user(user_id),
  status          VARCHAR(10)   NOT NULL CHECK (status IN ('Proposed','Approved','Rejected','Posted','Failed')),
  erp_reference   VARCHAR(30)
);

CREATE TABLE sales_transaction_line (
  txn_line_id       BIGINT      PRIMARY KEY,
  transaction_id    VARCHAR(30) NOT NULL,
  item_id           BIGINT      NOT NULL REFERENCES item(item_id),
  line_type         VARCHAR(6)  NOT NULL CHECK (line_type IN ('Sale','Return')),
  channel           VARCHAR(15) NOT NULL,
  return_condition  VARCHAR(12),
  first_read_at     TIMESTAMP,
  payment_at        TIMESTAMP
);

CREATE TABLE channel_availability (
  store_id       VARCHAR(10) NOT NULL REFERENCES store(store_id),
  sku_id         VARCHAR(20) NOT NULL REFERENCES sku(sku_id),
  channel        VARCHAR(10) NOT NULL,
  available_qty  INTEGER     NOT NULL,
  published_at   TIMESTAMP   NOT NULL,
  suppressed     BOOLEAN     NOT NULL DEFAULT 0,               -- BRULE-016
  PRIMARY KEY (store_id, sku_id, channel)
);

CREATE TABLE exception_record (
  exception_id    BIGINT      PRIMARY KEY,
  exception_type  VARCHAR(25) NOT NULL,
  store_id        VARCHAR(10) REFERENCES store(store_id),
  owner_role      VARCHAR(30) NOT NULL,
  due_at          TIMESTAMP   NOT NULL,
  status          VARCHAR(12) NOT NULL
);

CREATE TABLE audit_log (                                          -- append-only (BRULE-019)
  audit_id      BIGINT      PRIMARY KEY,
  event_type    VARCHAR(20) NOT NULL,
  entity_ref    VARCHAR(40) NOT NULL,
  user_id       VARCHAR(20) NOT NULL REFERENCES app_user(user_id),
  device_id     VARCHAR(20),
  before_value  TEXT,
  after_value   TEXT,
  reason        VARCHAR(80),
  occurred_at   TIMESTAMP   NOT NULL
);
