local p = import '../_params.libsonnet';
local c = (import '../../_common.libsonnet')(p);

c.taskDefBase(
  '{{ tfstate `module.app.aws_ecs_task_definition.main.family` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.main.cpu` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.main.memory` }}',
) + {
  containerDefinitions: [
    {
      name: 'nginx-container',
      image: '{{ tfstate `module.app.data.aws_ecr_repository.nginx.repository_url` }}:{{ must_env `IMAGE_TAG_NGINX` }}',
      portMappings: [
        { containerPort: 80, protocol: 'tcp' },
      ],
      logConfiguration: c.firelens('nginx/'),
    },
    {
      name: 'laravel-container',
      image: '{{ tfstate `module.app.data.aws_ecr_repository.laravel.repository_url` }}:{{ must_env `IMAGE_TAG_LARAVEL` }}',
      portMappings: [
        { containerPort: 9000, protocol: 'tcp' },
      ],
      environment: c.dbEnv + c.logEnv + c.appEnv + c.otelEnv + c.sqsEnv + c.mailEnv + c.sessionEnv + [
        { name: 'FRONTEND_URL', value: c.frontendUrl },
        { name: 'APP_URL', value: c.backendUrl },
        { name: 'AWS_BUCKET', value: '{{ tfstate `module.app.aws_s3_bucket.image_bucket.bucket` }}' },
        { name: 'AWS_URL', value: 'https://{{ tfstate `module.app.aws_cloudfront_distribution.image_cdn.domain_name` }}' },
        { name: 'APP_DEBUG', value: 'false' },
        { name: 'FILESYSTEM_DISK', value: 's3' },
        { name: 'GOOGLE_REDIRECT_URI', value: c.frontendUrl + '/api/auth/google/callback' },
      ],
      secrets: c.baseSecrets + [
        { name: 'GOOGLE_CLIENT_ID', valueFrom: '{{ tfstate `module.app.data.aws_ssm_parameter.google_client_id.arn` }}' },
        { name: 'GOOGLE_CLIENT_SECRET', valueFrom: '{{ tfstate `module.app.data.aws_ssm_parameter.google_client_secret.arn` }}' },
      ],
      logConfiguration: c.firelens('backend/'),
    },
    {
      name: 'log-router',
      image: 'public.ecr.aws/aws-observability/aws-for-fluent-bit:stable',
      essential: true,
      firelensConfiguration: {
        type: 'fluentbit',
        options: {
          'enable-ecs-log-metadata': 'true',
        },
      },
      logConfiguration: c.awslogs('firelens'),
    },
    {
      name: 'adot-collector',
      image: 'public.ecr.aws/aws-observability/aws-otel-collector:latest',
      essential: false,
      portMappings: [
        { containerPort: 4317, protocol: 'tcp' },
        { containerPort: 4318, protocol: 'tcp' },
      ],
      secrets: [
        { name: 'AOT_CONFIG_CONTENT', valueFrom: '{{ tfstate `module.app.aws_ssm_parameter.otel_collector_config.arn` }}' },
      ],
      logConfiguration: c.awslogs('adot'),
    },
  ],
}
