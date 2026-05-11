// stg 環境固有の値。Terraform でいう terraform.tfvars に相当。
// prod を作るときは ecspresso/prod/_params.libsonnet を新規作成し、ここの値を環境に合わせて書き換える。
{
  envName: 'stg',
  appEnv: 'staging',                         // Laravel の APP_ENV
  appName: 'practice',                       // Laravel の APP_NAME（env 横断で同じなら共通でも可）
  projectName: 'practice-stg',               // OTEL_SERVICE_NAME や各種プレフィックスに使用
  domain: 'mylabinfra.com',                  // 環境共通のルートドメイン
  frontendSubdomain: 'stg.www',              // → https://stg.www.mylabinfra.com
  backendSubdomain: 'stg.api',               // → https://stg.api.mylabinfra.com
  sqsQueueName: 'staging-qrcode-generation', // SQS キュー名（queue-worker の --queue= にも入る）
  mailFromName: 'practice-stg',              // メール From 表示名
}
