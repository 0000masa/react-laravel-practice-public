// 共通モジュール。p (params) を受け取り、env 横断で使い回せる値・ヘルパを返す。
// 使い方:
//   local p = import '../_params.libsonnet';            // ← env 固有値を p にロード
//   local c = (import '../../_common.libsonnet')(p);    // ← このファイル(関数)に p を渡して c に束縛
//                                                       //   (import '...') が関数本体、その後ろの (p) が引数渡し
function(p) {
  // === 環境変数グループ ===
  dbEnv: [
    { name: 'DB_DATABASE', value: '{{ tfstate `module.app.aws_db_instance.main.db_name` }}' },
    { name: 'DB_HOST', value: '{{ tfstate `module.app.aws_db_instance.main.address` }}' },
    { name: 'DB_PORT', value: '3306' },
    { name: 'DB_USERNAME', value: 'admin' },
    { name: 'DB_CONNECTION', value: 'mysql' },
  ],

  logEnv: [
    { name: 'LOG_CHANNEL', value: 'stderr' },
    { name: 'LOG_DEPRECATIONS_CHANNEL', value: 'stderr' },
  ],

  appEnv: [
    { name: 'AWS_DEFAULT_REGION', value: 'ap-northeast-1' },
    { name: 'AWS_USE_PATH_STYLE_ENDPOINT', value: 'false' },
    { name: 'APP_NAME', value: p.appName },
    { name: 'APP_ENV', value: p.appEnv },
  ],

  otelEnv: [
    { name: 'OTEL_PHP_AUTOLOAD_ENABLED', value: 'true' },
    { name: 'OTEL_SERVICE_NAME', value: p.projectName + '-backend' },
    { name: 'OTEL_TRACES_EXPORTER', value: 'otlp' },
    { name: 'OTEL_EXPORTER_OTLP_PROTOCOL', value: 'http/protobuf' },
    { name: 'OTEL_EXPORTER_OTLP_ENDPOINT', value: 'http://localhost:4318' },
    { name: 'OTEL_PROPAGATORS', value: 'baggage,tracecontext' },
  ],

  sqsEnv: [
    { name: 'QUEUE_CONNECTION', value: 'sqs' },
    { name: 'SQS_PREFIX', value: 'https://sqs.ap-northeast-1.amazonaws.com/{{ must_env `AWS_ACCOUNT_ID` }}' },
    { name: 'SQS_QUEUE', value: p.sqsQueueName },
  ],

  mailEnv: [
    { name: 'MAIL_MAILER', value: 'ses' },
    { name: 'MAIL_FROM_ADDRESS', value: 'noreply@%s.%s' % [p.frontendSubdomain, p.domain] },
    { name: 'MAIL_FROM_NAME', value: p.mailFromName },
  ],

  sessionEnv: [
    { name: 'SESSION_DRIVER', value: 'database' },
    { name: 'SESSION_LIFETIME', value: '120' },
    { name: 'SESSION_ENCRYPT', value: 'false' },
    { name: 'SESSION_PATH', value: '/' },
    { name: 'SESSION_SECURE', value: 'true' },
    { name: 'SESSION_SAME_SITE', value: 'lax' },
  ],

  // === 派生 URL ===
  frontendUrl: 'https://%s.%s' % [p.frontendSubdomain, p.domain],
  backendUrl: 'https://%s.%s' % [p.backendSubdomain, p.domain],

  // === 共通 secrets ===
  baseSecrets: [
    { name: 'DB_PASSWORD', valueFrom: '{{ tfstate `module.app.data.aws_ssm_parameter.db_password.arn` }}' },
    { name: 'APP_KEY', valueFrom: '{{ tfstate `module.app.data.aws_ssm_parameter.app_key.arn` }}' },
  ],

  // === ログ ===
  logGroup: '{{ tfstate `module.app.aws_cloudwatch_log_group.ecs_log.name` }}',

  awslogs(prefix):: {
    logDriver: 'awslogs',
    options: {
      'awslogs-group': $.logGroup,
      'awslogs-region': 'ap-northeast-1',
      'awslogs-stream-prefix': prefix,
    },
  },

  firelens(prefix):: {
    logDriver: 'awsfirelens',
    options: {
      Name: 'cloudwatch_logs',
      region: 'ap-northeast-1',
      log_group_name: $.logGroup,
      log_stream_prefix: prefix,
    },
  },

  // === タスク定義の共通骨格 ===
  taskDefBase(family, cpu, memory):: {
    family: family,
    networkMode: 'awsvpc',
    requiresCompatibilities: ['FARGATE'],
    cpu: cpu,
    memory: memory,
    // tfstate プラグインはネストしたモジュール出力を解決できないため、
    // ARN を AWS_ACCOUNT_ID + projectName から組み立てる（role 名は iam.tf で固定）
    executionRoleArn: 'arn:aws:iam::{{ must_env `AWS_ACCOUNT_ID` }}:role/' + p.projectName + '-execution-role',
    taskRoleArn: 'arn:aws:iam::{{ must_env `AWS_ACCOUNT_ID` }}:role/' + p.projectName + '-task-role',
  },

  // === サービス定義の共通パーツ ===
  fargateSpot:: { capacityProvider: 'FARGATE_SPOT', weight: 1, base: 0 },

  deploymentCircuitBreaker:: { enable: true, rollback: true },

  // subnet / security group は module.vpc 配下のため tfstate プラグインで解決できない。
  // ワークフロー側で SSM から取得し ECS_SUBNET_A_ID / ECS_SUBNET_C_ID / ECS_SECURITY_GROUP_ID を
  // GITHUB_ENV にエクスポートする前提。
  networkConfig:: {
    awsvpcConfiguration: {
      subnets: [
        '{{ must_env `ECS_SUBNET_A_ID` }}',
        '{{ must_env `ECS_SUBNET_C_ID` }}',
      ],
      securityGroups: ['{{ must_env `ECS_SECURITY_GROUP_ID` }}'],
      assignPublicIp: 'DISABLED',
    },
  },
}
