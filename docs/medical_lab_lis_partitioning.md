# مخطط احترافي لمنظومة مختبرات طبية ضخمة باستخدام PostgreSQL Table Partitioning

هذا المستودع لا يحتوي أصلًا على طبقة قاعدة بيانات أو migrations خاصة بمنظومة مختبرات، لذلك أضفت **مخططًا مستقلًا وقابلًا للتنفيذ** داخل PostgreSQL في الملف:

- `docs/medical_lab_lis_partitioned_postgresql.sql`

الهدف من هذا التصميم هو توفير **نواة LIS/LIMS احترافية** تناسب الأحجام الكبيرة جدًا، مع تقسيم للجداول الثقيلة يقلل زمن الاستعلامات ويحسن أداء الإدخال والصيانة والأرشفة.

## 1) الفكرة العامة للتصميم

تم تقسيم الجداول إلى نوعين:

### جداول مرجعية Reference / Master Data

هذه الجداول لا تحتاج partitioning غالبًا لأنها أقل نموًا من الجداول التشغيلية:

- `lis.organizations`
- `lis.lab_sites`
- `lis.staff_users`
- `lis.providers`
- `lis.patients`
- `lis.specimen_types`
- `lis.tests`
- `lis.test_panel_members`
- `lis.test_analytes`
- `lis.instruments`

### جداول تشغيلية High-Volume Transaction Tables

هذه هي الجداول التي تنمو بسرعة في أي منظومة مختبرات ضخمة، لذلك تم تصميمها كجداول partitioned:

- `lis.lab_orders`
- `lis.order_tests`
- `lis.specimens`
- `lis.specimen_tests`
- `lis.test_results`
- `lis.audit_events`

## 2) استراتيجية الـ Partitioning

### لماذا هذا الأسلوب؟

في منظومات المختبرات الضخمة، الأحمال الأعلى تكون عادة في:

- أوامر الفحوصات اليومية
- العينات والباركودات
- النتائج والتحقق والإطلاق
- سجلات التدقيق Audit Logs

ولهذا تم اختيار:

### A. Monthly RANGE partitioning

التقسيم الأساسي زمني شهري:

- الأوامر حسب `ordered_on`
- العينات حسب `collected_on`
- النتائج حسب `resulted_on`
- التدقيق حسب `event_on`

هذا يسمح بـ:

- **partition pruning** عند البحث في نطاق زمني محدد
- تسريع عمليات الأرشفة والحذف
- تقليل حجم الـ VACUUM/REINDEX لكل جزء
- تحسين الأداء في الأنظمة التي تتعامل مع سنوات طويلة من البيانات

### B. HASH subpartitioning by `site_id`

داخل الجداول التشغيلية الأعلى كتابة، تمت إضافة **hash subpartitions** على `site_id`:

- `lab_orders`
- `order_tests`
- `specimens`
- `specimen_tests`
- `test_results`

وهذا مفيد عندما تكون الشبكة تحتوي على:

- مختبر مركزي + فروع
- مراكز سحب متعددة
- عدة مواقع تعمل بالتوازي

النتيجة:

- توزيع أفضل للكتابة
- تقليل التنافس على نفس partition leaf
- قابلية توسع أفضل مع ارتفاع عدد الفروع

## 3) لماذا توجد أعمدة مثل `ordered_on` و `collected_on` و `resulted_on`؟

هذه أعمدة **business dates** صريحة، وتم استخدامها كمفاتيح partition.

في PostgreSQL، القيد المهم هو أن:

> أي `PRIMARY KEY` أو `UNIQUE` على جدول partitioned يجب أن يشمل مفتاح الـ partition.

لذلك تم تصميم المفاتيح بالشكل التالي:

- `lab_orders` -> `PRIMARY KEY (ordered_on, order_id)`
- `order_tests` -> `PRIMARY KEY (ordered_on, order_id, order_test_id)`
- `specimens` -> `PRIMARY KEY (collected_on, specimen_id)`
- `test_results` -> `PRIMARY KEY (resulted_on, result_id)`

هذا تصميم مقصود وليس عيبًا، وهو من أفضل الممارسات عند بناء مخطط PostgreSQL partitioned بشكل native.

## 4) أهم الجداول التشغيلية

### `lis.lab_orders`

تمثل الطلب الرئيسي للفحوصات، وتشمل:

- المنظمة / الفرع
- المريض
- الطبيب المحول
- رقم الطلب الخارجي
- الأولوية
- الحالة
- وقت الطلب والاستلام

### `lis.order_tests`

تمثل الأسطر الداخلية داخل الطلب الواحد:

- كل فحص مطلوب
- نوع العينة المطلوب
- الموقع المنفذ
- حالة الفحص
- موعد TAT المتوقع

### `lis.specimens`

تمثل العينات الفيزيائية:

- accession number
- barcode
- وقت الجمع
- وقت الاستلام
- حالة العينة
- موقع التخزين
- سبب الرفض إن وجد

### `lis.specimen_tests`

تمثل الربط بين العينة والفحوصات المطلوبة، لأن:

- عينة واحدة قد تخدم عدة فحوصات
- وبعض الفحوصات قد تحتاج عينات مختلفة

### `lis.test_results`

تمثل النتائج على مستوى analyte:

- الربط مع `order_tests`
- الربط مع العينة إن وجدت
- الربط مع analyte
- القيمة الرقمية أو النصية أو المرمزة أو المنطقية
- flags غير الطبيعية والحرجة
- أوقات الملاحظة والتحقق والإطلاق

### `lis.audit_events`

سجل immutable للتغييرات التشغيلية، وهو مهم جدًا في بيئات المختبرات والاعتمادات.

## 5) View جاهز للنتائج النهائية

تمت إضافة:

- `lis.v_latest_released_results`

وهو يعرض **آخر نتيجة نهائية/متحقق منها** لكل:

- طلب
- فحص
- analyte

وهذا مفيد جدًا للـ dashboards والربط مع HIS/EMR.

## 6) إدارة الـ partitions

تمت إضافة 3 دوال:

- `lis.create_monthly_hash_partition(...)`
- `lis.create_monthly_range_partition(...)`
- `lis.ensure_lis_partitions(...)`

والملف يقوم تلقائيًا بإنشاء:

- partition للشهر السابق
- وحتى 18 شهرًا قادمة
- مع 8 hash buckets لكل الجداول الثقيلة

### مثال تشغيل دوري

يفضل تشغيل هذا الاستدعاء مجدولًا مرة شهريًا:

```sql
SELECT lis.ensure_lis_partitions(
    date_trunc('month', current_date)::date,
    6,
    8
);
```

## 7) تشغيل المخطط

يمكن تنفيذ الملف مباشرة بواسطة:

```bash
psql "$DATABASE_URL" -f docs/medical_lab_lis_partitioned_postgresql.sql
```

## 8) توصيات تشغيلية مهمة

### أنماط الاستعلام

حتى تستفيد فعليًا من الـ partition pruning:

- ضمّن دائمًا شرطًا على التاريخ:
  - `ordered_on`
  - `collected_on`
  - `resulted_on`
  - `event_on`
- وحاول أيضًا تضمين `site_id` عند الاستعلامات المحلية

### الأرشفة والاحتفاظ

لأن كل شهر عبارة عن partition مستقل، يصبح من السهل:

- نقل partitions القديمة إلى أرشيف
- أو `DETACH PARTITION`
- أو `DROP` بعد الاحتفاظ النظامي

### البحث العالمي بالـ accession أو external order number

إذا كانت لديك متطلبات بحث كثيف عبر سنوات طويلة بدون تاريخ، فالأفضل لاحقًا إضافة:

- lookup tables غير مقسمة
- أو search index مخصص

لأن الاستعلامات التي لا تحتوي على تاريخ قد تمر على partitions كثيرة.

## 9) لماذا هذا التصميم مناسب لمنظومة مختبرات ضخمة؟

لأنه يوازن بين:

- **المرونة التشغيلية**
- **سهولة التطوير**
- **أداء القراءة والكتابة**
- **إدارة الأرشفة**
- **متطلبات التتبع والتدقيق**

كما أنه يترك مساحة سهلة للتوسع لاحقًا بإضافة:

- billing
- microbiology workflows
- histopathology
- HL7/FHIR integration
- queueing / instrumentation middleware
- SLA/TAT analytics

## 10) الخطوة التالية

إذا أردت، أستطيع في الخطوة التالية تحويل هذا المخطط إلى واحد من الأشكال التالية بحسب تقنيتك الفعلية:

- Prisma schema + SQL migrations
- Laravel migrations
- Django models/migrations
- TypeORM / Sequelize / Knex
- PostgreSQL migration files منظّمة على مراحل

