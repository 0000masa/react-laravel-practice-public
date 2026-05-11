local p = import '../_params.libsonnet';
local c = (import '../../_common.libsonnet')(p);

{
  desiredCount: 1,
  capacityProviderStrategy: [c.fargateSpot],
  deploymentConfiguration: {
    minimumHealthyPercent: 100,
    maximumPercent: 200,
    deploymentCircuitBreaker: c.deploymentCircuitBreaker,
  },
  networkConfiguration: c.networkConfig,
}
