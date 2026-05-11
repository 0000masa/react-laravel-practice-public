local p = import '../_params.libsonnet';
local c = (import '../../_common.libsonnet')(p);

c.taskDefBase(
  '{{ tfstate `module.app.aws_ecs_task_definition.queue_worker.family` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.queue_worker.cpu` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.queue_worker.memory` }}',
) + {
  containerDefinitions: [
    {
      name: 'queue-worker-container',
      image: '{{ tfstate `module.app.data.aws_ecr_repository.laravel.repository_url` }}:{{ must_env `IMAGE_TAG_LARAVEL` }}',
      essential: true,
      command: ['php', 'artisan', 'queue:work', 'sqs', '--queue=' + p.sqsQueueName, '--tries=3', '--timeout=60'],
      environment: c.dbEnv + c.logEnv + c.appEnv + c.sqsEnv + [
        { name: 'APP_URL', value: c.backendUrl },
        { name: 'AWS_BUCKET', value: '{{ tfstate `module.app.aws_s3_bucket.image_bucket.bucket` }}' },
        { name: 'AWS_URL', value: 'https://{{ tfstate `module.app.aws_cloudfront_distribution.image_cdn.domain_name` }}' },
        { name: 'APP_DEBUG', value: 'false' },
        { name: 'FILESYSTEM_DISK', value: 's3' },
      ],
      secrets: c.baseSecrets,
      logConfiguration: c.awslogs('ecs'),
    },
  ],
}
