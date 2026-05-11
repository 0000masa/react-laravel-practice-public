local p = import '../_params.libsonnet';
local c = (import '../../_common.libsonnet')(p);

c.taskDefBase(
  '{{ tfstate `module.app.aws_ecs_task_definition.batch_daily_report.family` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.batch_daily_report.cpu` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.batch_daily_report.memory` }}',
) + {
  containerDefinitions: [
    {
      name: 'batch-container',
      image: '{{ tfstate `module.app.data.aws_ecr_repository.laravel.repository_url` }}:{{ must_env `IMAGE_TAG_LARAVEL` }}',
      essential: true,
      command: ['php', 'artisan', 'report:daily'],
      environment: c.dbEnv + c.logEnv + c.appEnv + c.mailEnv + [
        { name: 'APP_DEBUG', value: 'false' },
      ],
      secrets: c.baseSecrets,
      logConfiguration: c.awslogs('ecs'),
    },
  ],
}
