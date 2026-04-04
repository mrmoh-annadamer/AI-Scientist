BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS lis;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'lis' AND t.typname = 'patient_gender'
    ) THEN
        CREATE TYPE lis.patient_gender AS ENUM ('male', 'female', 'other', 'unknown');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'lis' AND t.typname = 'order_priority'
    ) THEN
        CREATE TYPE lis.order_priority AS ENUM ('routine', 'urgent', 'stat');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'lis' AND t.typname = 'order_status'
    ) THEN
        CREATE TYPE lis.order_status AS ENUM (
            'draft',
            'received',
            'in_progress',
            'partial',
            'completed',
            'cancelled',
            'rejected'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'lis' AND t.typname = 'order_test_status'
    ) THEN
        CREATE TYPE lis.order_test_status AS ENUM (
            'ordered',
            'received',
            'processing',
            'partial',
            'completed',
            'released',
            'cancelled',
            'rejected'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'lis' AND t.typname = 'specimen_status'
    ) THEN
        CREATE TYPE lis.specimen_status AS ENUM (
            'collected',
            'received',
            'processing',
            'stored',
            'disposed',
            'rejected'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'lis' AND t.typname = 'specimen_assignment_status'
    ) THEN
        CREATE TYPE lis.specimen_assignment_status AS ENUM ('assigned', 'consumed', 'cancelled');
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'lis' AND t.typname = 'result_status'
    ) THEN
        CREATE TYPE lis.result_status AS ENUM (
            'entered',
            'validated',
            'released',
            'corrected',
            'cancelled'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'lis' AND t.typname = 'result_value_kind'
    ) THEN
        CREATE TYPE lis.result_value_kind AS ENUM ('numeric', 'text', 'coded', 'boolean');
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION lis.set_row_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS lis.organizations (
    organization_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_code varchar(30) NOT NULL UNIQUE,
    organization_name text NOT NULL,
    default_timezone text NOT NULL DEFAULT 'UTC',
    retention_months integer NOT NULL DEFAULT 84 CHECK (retention_months >= 12),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS lis.lab_sites (
    site_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_code varchar(30) NOT NULL,
    site_name text NOT NULL,
    site_type varchar(30) NOT NULL CHECK (
        site_type IN ('central_lab', 'branch_lab', 'collection_center', 'hospital_lab')
    ),
    country_code char(2) NOT NULL,
    city text,
    address_line text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, site_code)
);

CREATE TABLE IF NOT EXISTS lis.staff_users (
    staff_user_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_id uuid REFERENCES lis.lab_sites (site_id),
    username varchar(80) NOT NULL,
    full_name text NOT NULL,
    role_code varchar(40) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, username)
);

CREATE TABLE IF NOT EXISTS lis.providers (
    provider_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_id uuid REFERENCES lis.lab_sites (site_id),
    provider_code varchar(40) NOT NULL,
    full_name text NOT NULL,
    license_number varchar(60),
    specialty varchar(80),
    phone varchar(30),
    email varchar(120),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, provider_code)
);

CREATE TABLE IF NOT EXISTS lis.patients (
    patient_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    mrn varchar(40) NOT NULL,
    national_id varchar(40),
    first_name varchar(120) NOT NULL,
    middle_name varchar(120),
    last_name varchar(120) NOT NULL,
    date_of_birth date,
    gender lis.patient_gender NOT NULL DEFAULT 'unknown',
    phone varchar(30),
    email varchar(120),
    blood_group varchar(8),
    is_deceased boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, mrn)
);

CREATE TABLE IF NOT EXISTS lis.specimen_types (
    specimen_type_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    specimen_type_code varchar(30) NOT NULL UNIQUE,
    specimen_type_name text NOT NULL,
    default_container varchar(80),
    storage_temperature varchar(80),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS lis.tests (
    test_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    test_code varchar(40) NOT NULL,
    test_name text NOT NULL,
    discipline varchar(40) NOT NULL,
    loinc_code varchar(30),
    specimen_type_id bigint NOT NULL REFERENCES lis.specimen_types (specimen_type_id),
    default_tat_minutes integer NOT NULL DEFAULT 60 CHECK (default_tat_minutes > 0),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (organization_id, test_code)
);

CREATE TABLE IF NOT EXISTS lis.test_panel_members (
    parent_test_id bigint NOT NULL REFERENCES lis.tests (test_id) ON DELETE CASCADE,
    child_test_id bigint NOT NULL REFERENCES lis.tests (test_id),
    display_sequence smallint NOT NULL DEFAULT 1,
    is_mandatory boolean NOT NULL DEFAULT true,
    PRIMARY KEY (parent_test_id, child_test_id)
);

CREATE TABLE IF NOT EXISTS lis.test_analytes (
    analyte_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    test_id bigint NOT NULL REFERENCES lis.tests (test_id) ON DELETE CASCADE,
    analyte_code varchar(40) NOT NULL,
    analyte_name text NOT NULL,
    value_kind lis.result_value_kind NOT NULL,
    unit_of_measure varchar(40),
    reference_low numeric(18, 6),
    reference_high numeric(18, 6),
    reference_text text,
    critical_low numeric(18, 6),
    critical_high numeric(18, 6),
    display_sequence smallint NOT NULL DEFAULT 1,
    UNIQUE (test_id, analyte_code)
);

CREATE TABLE IF NOT EXISTS lis.instruments (
    instrument_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_id uuid NOT NULL REFERENCES lis.lab_sites (site_id),
    instrument_code varchar(40) NOT NULL,
    instrument_name text NOT NULL,
    vendor_name varchar(120),
    model_name varchar(120),
    serial_number varchar(120),
    interface_protocol varchar(80),
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id, instrument_code)
);

CREATE TABLE IF NOT EXISTS lis.lab_orders (
    ordered_on date NOT NULL,
    order_id bigint GENERATED ALWAYS AS IDENTITY,
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_id uuid NOT NULL REFERENCES lis.lab_sites (site_id),
    patient_id uuid NOT NULL REFERENCES lis.patients (patient_id),
    provider_id uuid REFERENCES lis.providers (provider_id),
    external_order_no varchar(60) NOT NULL,
    visit_no varchar(60),
    priority lis.order_priority NOT NULL DEFAULT 'routine',
    status lis.order_status NOT NULL DEFAULT 'received',
    fasting_required boolean NOT NULL DEFAULT false,
    diagnosis_text text,
    clinical_notes text,
    source_system varchar(60),
    ordered_at timestamptz NOT NULL,
    received_at timestamptz,
    created_by_user_id uuid REFERENCES lis.staff_users (staff_user_id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ordered_on, order_id),
    UNIQUE (organization_id, ordered_on, external_order_no),
    CHECK (ordered_on = (ordered_at AT TIME ZONE 'UTC')::date)
) PARTITION BY RANGE (ordered_on);

CREATE TABLE IF NOT EXISTS lis.order_tests (
    ordered_on date NOT NULL,
    order_id bigint NOT NULL,
    order_test_id bigint GENERATED ALWAYS AS IDENTITY,
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_id uuid NOT NULL REFERENCES lis.lab_sites (site_id),
    test_id bigint NOT NULL REFERENCES lis.tests (test_id),
    specimen_type_id bigint NOT NULL REFERENCES lis.specimen_types (specimen_type_id),
    performing_site_id uuid REFERENCES lis.lab_sites (site_id),
    requested_by_user_id uuid REFERENCES lis.staff_users (staff_user_id),
    priority lis.order_priority NOT NULL DEFAULT 'routine',
    status lis.order_test_status NOT NULL DEFAULT 'ordered',
    tat_due_at timestamptz,
    cancelled_at timestamptz,
    cancellation_reason text,
    price_amount numeric(12, 2),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ordered_on, order_id, order_test_id),
    FOREIGN KEY (ordered_on, order_id)
        REFERENCES lis.lab_orders (ordered_on, order_id)
        ON DELETE CASCADE
) PARTITION BY RANGE (ordered_on);

CREATE TABLE IF NOT EXISTS lis.specimens (
    collected_on date NOT NULL,
    specimen_id bigint GENERATED ALWAYS AS IDENTITY,
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_id uuid NOT NULL REFERENCES lis.lab_sites (site_id),
    ordered_on date NOT NULL,
    order_id bigint NOT NULL,
    accession_no varchar(60) NOT NULL,
    specimen_type_id bigint NOT NULL REFERENCES lis.specimen_types (specimen_type_id),
    barcode varchar(80),
    status lis.specimen_status NOT NULL DEFAULT 'collected',
    collected_at timestamptz NOT NULL,
    received_at timestamptz,
    collector_user_id uuid REFERENCES lis.staff_users (staff_user_id),
    storage_location varchar(120),
    rejection_reason text,
    volume_ml numeric(10, 2),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (collected_on, specimen_id),
    UNIQUE (site_id, collected_on, accession_no),
    FOREIGN KEY (ordered_on, order_id)
        REFERENCES lis.lab_orders (ordered_on, order_id)
        ON DELETE CASCADE,
    CHECK (collected_on = (collected_at AT TIME ZONE 'UTC')::date)
) PARTITION BY RANGE (collected_on);

CREATE TABLE IF NOT EXISTS lis.specimen_tests (
    collected_on date NOT NULL,
    specimen_id bigint NOT NULL,
    ordered_on date NOT NULL,
    order_id bigint NOT NULL,
    order_test_id bigint NOT NULL,
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_id uuid NOT NULL REFERENCES lis.lab_sites (site_id),
    assignment_status lis.specimen_assignment_status NOT NULL DEFAULT 'assigned',
    assigned_at timestamptz NOT NULL DEFAULT now(),
    notes text,
    PRIMARY KEY (collected_on, specimen_id, order_test_id),
    FOREIGN KEY (collected_on, specimen_id)
        REFERENCES lis.specimens (collected_on, specimen_id)
        ON DELETE CASCADE,
    FOREIGN KEY (ordered_on, order_id, order_test_id)
        REFERENCES lis.order_tests (ordered_on, order_id, order_test_id)
        ON DELETE CASCADE
) PARTITION BY RANGE (collected_on);

CREATE TABLE IF NOT EXISTS lis.test_results (
    resulted_on date NOT NULL,
    result_id bigint GENERATED ALWAYS AS IDENTITY,
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_id uuid NOT NULL REFERENCES lis.lab_sites (site_id),
    ordered_on date NOT NULL,
    order_id bigint NOT NULL,
    order_test_id bigint NOT NULL,
    collected_on date,
    specimen_id bigint,
    analyte_id bigint NOT NULL REFERENCES lis.test_analytes (analyte_id),
    instrument_id uuid REFERENCES lis.instruments (instrument_id),
    result_status lis.result_status NOT NULL DEFAULT 'entered',
    value_kind lis.result_value_kind NOT NULL,
    result_numeric numeric(20, 6),
    result_text text,
    result_code varchar(60),
    result_boolean boolean,
    unit_of_measure varchar(40),
    reference_low numeric(18, 6),
    reference_high numeric(18, 6),
    reference_text text,
    abnormal_flag varchar(16),
    critical_flag boolean NOT NULL DEFAULT false,
    observed_at timestamptz NOT NULL,
    verified_at timestamptz,
    released_at timestamptz,
    entered_by_user_id uuid REFERENCES lis.staff_users (staff_user_id),
    verified_by_user_id uuid REFERENCES lis.staff_users (staff_user_id),
    comments text,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (resulted_on, result_id),
    FOREIGN KEY (ordered_on, order_id, order_test_id)
        REFERENCES lis.order_tests (ordered_on, order_id, order_test_id)
        ON DELETE CASCADE,
    FOREIGN KEY (collected_on, specimen_id)
        REFERENCES lis.specimens (collected_on, specimen_id),
    CHECK (resulted_on = (observed_at AT TIME ZONE 'UTC')::date),
    CHECK (
        (value_kind = 'numeric' AND result_numeric IS NOT NULL)
        OR (value_kind = 'text' AND result_text IS NOT NULL)
        OR (value_kind = 'coded' AND result_code IS NOT NULL)
        OR (value_kind = 'boolean' AND result_boolean IS NOT NULL)
    )
) PARTITION BY RANGE (resulted_on);

CREATE TABLE IF NOT EXISTS lis.audit_events (
    event_on date NOT NULL,
    event_id bigint GENERATED ALWAYS AS IDENTITY,
    organization_id uuid NOT NULL REFERENCES lis.organizations (organization_id),
    site_id uuid REFERENCES lis.lab_sites (site_id),
    actor_user_id uuid REFERENCES lis.staff_users (staff_user_id),
    actor_role varchar(40),
    entity_type varchar(80) NOT NULL,
    entity_pk jsonb NOT NULL,
    action_name varchar(80) NOT NULL,
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    source_system varchar(60),
    correlation_id uuid,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (event_on, event_id),
    CHECK (event_on = (occurred_at AT TIME ZONE 'UTC')::date)
) PARTITION BY RANGE (event_on);

CREATE INDEX IF NOT EXISTS ix_patients_org_national_id
    ON lis.patients (organization_id, national_id);

CREATE INDEX IF NOT EXISTS ix_tests_org_discipline
    ON lis.tests (organization_id, discipline, is_active);

CREATE INDEX IF NOT EXISTS ix_lab_orders_patient
    ON lis.lab_orders (organization_id, patient_id, ordered_on DESC);

CREATE INDEX IF NOT EXISTS ix_lab_orders_site_status
    ON lis.lab_orders (site_id, status, ordered_on DESC);

CREATE INDEX IF NOT EXISTS ix_lab_orders_ordered_at
    ON lis.lab_orders (ordered_at DESC);

CREATE INDEX IF NOT EXISTS ix_order_tests_test_status
    ON lis.order_tests (organization_id, test_id, status, ordered_on DESC);

CREATE INDEX IF NOT EXISTS ix_order_tests_performing_site
    ON lis.order_tests (performing_site_id, status, ordered_on DESC);

CREATE INDEX IF NOT EXISTS ix_specimens_order_ref
    ON lis.specimens (ordered_on, order_id);

CREATE INDEX IF NOT EXISTS ix_specimens_site_status
    ON lis.specimens (site_id, status, collected_on DESC);

CREATE INDEX IF NOT EXISTS ix_specimens_barcode
    ON lis.specimens (barcode);

CREATE INDEX IF NOT EXISTS ix_specimen_tests_order_test
    ON lis.specimen_tests (ordered_on, order_id, order_test_id);

CREATE INDEX IF NOT EXISTS ix_test_results_order_test_analyte
    ON lis.test_results (
        ordered_on,
        order_id,
        order_test_id,
        analyte_id,
        resulted_on DESC
    );

CREATE INDEX IF NOT EXISTS ix_test_results_site_status
    ON lis.test_results (site_id, result_status, resulted_on DESC);

CREATE INDEX IF NOT EXISTS ix_test_results_instrument
    ON lis.test_results (instrument_id, resulted_on DESC);

CREATE INDEX IF NOT EXISTS ix_audit_events_entity
    ON lis.audit_events (entity_type, event_on DESC);

CREATE INDEX IF NOT EXISTS ix_audit_events_correlation
    ON lis.audit_events (correlation_id);

CREATE INDEX IF NOT EXISTS ix_audit_events_payload_gin
    ON lis.audit_events USING gin (event_payload);

CREATE OR REPLACE VIEW lis.v_latest_released_results AS
SELECT DISTINCT ON (tr.ordered_on, tr.order_id, tr.order_test_id, tr.analyte_id)
    tr.resulted_on,
    tr.result_id,
    tr.organization_id,
    tr.site_id,
    tr.ordered_on,
    tr.order_id,
    tr.order_test_id,
    tr.collected_on,
    tr.specimen_id,
    tr.analyte_id,
    tr.instrument_id,
    tr.result_status,
    tr.value_kind,
    tr.result_numeric,
    tr.result_text,
    tr.result_code,
    tr.result_boolean,
    tr.unit_of_measure,
    tr.reference_low,
    tr.reference_high,
    tr.reference_text,
    tr.abnormal_flag,
    tr.critical_flag,
    tr.observed_at,
    tr.verified_at,
    tr.released_at,
    tr.entered_by_user_id,
    tr.verified_by_user_id,
    tr.comments,
    tr.created_at
FROM lis.test_results tr
WHERE tr.result_status IN ('validated', 'released', 'corrected')
ORDER BY
    tr.ordered_on,
    tr.order_id,
    tr.order_test_id,
    tr.analyte_id,
    COALESCE(tr.released_at, tr.verified_at, tr.observed_at) DESC,
    tr.result_id DESC;

COMMENT ON TABLE lis.lab_orders IS
    'High-volume parent table. Partition by ordered_on (monthly range) with hash subpartitions by site_id.';
COMMENT ON TABLE lis.order_tests IS
    'Order line items aligned to lab_orders and partitioned by the same business date for pruning and FK locality.';
COMMENT ON TABLE lis.specimens IS
    'Physical specimen tracking table partitioned by collected_on (monthly range) with hash subpartitions by site_id.';
COMMENT ON TABLE lis.test_results IS
    'Analyte-level result fact table partitioned by resulted_on (monthly range) with hash subpartitions by site_id.';
COMMENT ON TABLE lis.audit_events IS
    'Immutable operational audit trail partitioned monthly by event_on.';

CREATE OR REPLACE FUNCTION lis.create_monthly_hash_partition(
    p_parent regclass,
    p_month date,
    p_hash_column name,
    p_hash_partitions integer DEFAULT 8
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    parent_schema name;
    parent_name name;
    month_start date := date_trunc('month', p_month)::date;
    month_end date := (date_trunc('month', p_month) + interval '1 month')::date;
    partition_name text;
    subpartition_name text;
    bucket integer;
BEGIN
    IF p_hash_partitions < 1 THEN
        RAISE EXCEPTION 'p_hash_partitions must be >= 1';
    END IF;

    SELECT n.nspname, c.relname
      INTO parent_schema, parent_name
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.oid = p_parent;

    IF parent_name IS NULL THEN
        RAISE EXCEPTION 'Parent table % not found', p_parent::text;
    END IF;

    partition_name := format('%s_%s', parent_name, to_char(month_start, 'YYYYMM'));

    IF to_regclass(format('%I.%I', parent_schema, partition_name)) IS NULL THEN
        EXECUTE format(
            'CREATE TABLE %I.%I PARTITION OF %s FOR VALUES FROM (%L) TO (%L) PARTITION BY HASH (%I)',
            parent_schema,
            partition_name,
            p_parent::text,
            month_start,
            month_end,
            p_hash_column
        );
    END IF;

    FOR bucket IN 0..p_hash_partitions - 1 LOOP
        subpartition_name := format('%s_p%s', partition_name, bucket);

        IF to_regclass(format('%I.%I', parent_schema, subpartition_name)) IS NULL THEN
            EXECUTE format(
                'CREATE TABLE %I.%I PARTITION OF %I.%I FOR VALUES WITH (MODULUS %s, REMAINDER %s)',
                parent_schema,
                subpartition_name,
                parent_schema,
                partition_name,
                p_hash_partitions,
                bucket
            );
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION lis.create_monthly_range_partition(
    p_parent regclass,
    p_month date
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    parent_schema name;
    parent_name name;
    month_start date := date_trunc('month', p_month)::date;
    month_end date := (date_trunc('month', p_month) + interval '1 month')::date;
    partition_name text;
BEGIN
    SELECT n.nspname, c.relname
      INTO parent_schema, parent_name
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.oid = p_parent;

    IF parent_name IS NULL THEN
        RAISE EXCEPTION 'Parent table % not found', p_parent::text;
    END IF;

    partition_name := format('%s_%s', parent_name, to_char(month_start, 'YYYYMM'));

    IF to_regclass(format('%I.%I', parent_schema, partition_name)) IS NULL THEN
        EXECUTE format(
            'CREATE TABLE %I.%I PARTITION OF %s FOR VALUES FROM (%L) TO (%L)',
            parent_schema,
            partition_name,
            p_parent::text,
            month_start,
            month_end
        );
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION lis.ensure_lis_partitions(
    p_start_month date DEFAULT date_trunc('month', current_date)::date,
    p_month_count integer DEFAULT 18,
    p_hash_partitions integer DEFAULT 8
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    month_cursor date;
BEGIN
    IF p_month_count < 1 THEN
        RAISE EXCEPTION 'p_month_count must be >= 1';
    END IF;

    FOR month_cursor IN
        SELECT (date_trunc('month', p_start_month)::date + make_interval(months => gs))::date
        FROM generate_series(0, p_month_count - 1) AS gs
    LOOP
        PERFORM lis.create_monthly_hash_partition('lis.lab_orders', month_cursor, 'site_id', p_hash_partitions);
        PERFORM lis.create_monthly_hash_partition('lis.order_tests', month_cursor, 'site_id', p_hash_partitions);
        PERFORM lis.create_monthly_hash_partition('lis.specimens', month_cursor, 'site_id', p_hash_partitions);
        PERFORM lis.create_monthly_hash_partition('lis.specimen_tests', month_cursor, 'site_id', p_hash_partitions);
        PERFORM lis.create_monthly_hash_partition('lis.test_results', month_cursor, 'site_id', p_hash_partitions);
        PERFORM lis.create_monthly_range_partition('lis.audit_events', month_cursor);
    END LOOP;
END;
$$;

COMMENT ON FUNCTION lis.ensure_lis_partitions(date, integer, integer) IS
    'Pre-creates monthly partitions for operational LIS tables and hash subpartitions for high-write workloads.';

DROP TRIGGER IF EXISTS trg_organizations_updated_at ON lis.organizations;
CREATE TRIGGER trg_organizations_updated_at
BEFORE UPDATE ON lis.organizations
FOR EACH ROW
EXECUTE FUNCTION lis.set_row_updated_at();

DROP TRIGGER IF EXISTS trg_lab_sites_updated_at ON lis.lab_sites;
CREATE TRIGGER trg_lab_sites_updated_at
BEFORE UPDATE ON lis.lab_sites
FOR EACH ROW
EXECUTE FUNCTION lis.set_row_updated_at();

DROP TRIGGER IF EXISTS trg_staff_users_updated_at ON lis.staff_users;
CREATE TRIGGER trg_staff_users_updated_at
BEFORE UPDATE ON lis.staff_users
FOR EACH ROW
EXECUTE FUNCTION lis.set_row_updated_at();

DROP TRIGGER IF EXISTS trg_providers_updated_at ON lis.providers;
CREATE TRIGGER trg_providers_updated_at
BEFORE UPDATE ON lis.providers
FOR EACH ROW
EXECUTE FUNCTION lis.set_row_updated_at();

DROP TRIGGER IF EXISTS trg_patients_updated_at ON lis.patients;
CREATE TRIGGER trg_patients_updated_at
BEFORE UPDATE ON lis.patients
FOR EACH ROW
EXECUTE FUNCTION lis.set_row_updated_at();

DROP TRIGGER IF EXISTS trg_tests_updated_at ON lis.tests;
CREATE TRIGGER trg_tests_updated_at
BEFORE UPDATE ON lis.tests
FOR EACH ROW
EXECUTE FUNCTION lis.set_row_updated_at();

DROP TRIGGER IF EXISTS trg_instruments_updated_at ON lis.instruments;
CREATE TRIGGER trg_instruments_updated_at
BEFORE UPDATE ON lis.instruments
FOR EACH ROW
EXECUTE FUNCTION lis.set_row_updated_at();

SELECT lis.ensure_lis_partitions(
    (date_trunc('month', current_date) - interval '1 month')::date,
    18,
    8
);

COMMIT;
