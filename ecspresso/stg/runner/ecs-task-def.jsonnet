local p = import '../_params.libsonnet';
local c = (import '../../_common.libsonnet')(p);

// migrate / seed / 任意 shell を db-task.yml の containerOverrides で切替実行する
// 汎用ランナー。タスク定義側に command は持たず、必ず実行時に上書きする前提。
c.taskDefBase(
  '{{ tfstate `module.app.aws_ecs_task_definition.runner.family` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.runner.cpu` }}',
  '{{ tfstate `module.app.aws_ecs_task_definition.runner.memory` }}',
) + {
  containerDefinitions: [
    {
      name: 'runner-container',
      image: '{{ tfstate `module.app.data.aws_ecr_repository.laravel.repository_url` }}:{{ must_env `IMAGE_TAG_LARAVEL` }}',
      environment: c.dbEnv + c.logEnv + c.appEnv,
      secrets: c.baseSecrets,
      logConfiguration: c.awslogs('runner'),
    },
  ],
}
