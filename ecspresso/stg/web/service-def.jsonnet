local p = import '../_params.libsonnet';
local c = (import '../../_common.libsonnet')(p);

{
  desiredCount: 1,
  enableExecuteCommand: true,
  capacityProviderStrategy: [c.fargateSpot],
  deploymentConfiguration: {
    minimumHealthyPercent: 100,
    maximumPercent: 200,
    strategy: 'BLUE_GREEN',
    bakeTimeInMinutes: 0,
    deploymentCircuitBreaker: c.deploymentCircuitBreaker,
  },
  networkConfiguration: c.networkConfig,
  loadBalancers: [
    {
      targetGroupArn: '{{ tfstate `module.app.aws_lb_target_group.slot_a.arn` }}',
      containerName: 'nginx-container',
      containerPort: 80,
      advancedConfiguration: {
        alternateTargetGroupArn: '{{ tfstate `module.app.aws_lb_target_group.slot_b.arn` }}',
        productionListenerRule: '{{ tfstate `module.app.aws_lb_listener_rule.ecs_production.arn` }}',
        testListenerRule: '{{ tfstate `module.app.aws_lb_listener_rule.ecs_test.arn` }}',
        // ECS Infra LB role は terraform-aws-modules/iam/aws の nested module で
        // tfstate からは解決できないため projectName 命名規則で ARN を組み立てる
        // (taskDefBase が executionRoleArn / taskRoleArn を組み立てるのと同じ理由)
        roleArn: 'arn:aws:iam::{{ must_env `AWS_ACCOUNT_ID` }}:role/' + p.projectName + '-ecs-infra-lb-role',
      },
    },
  ],
}
