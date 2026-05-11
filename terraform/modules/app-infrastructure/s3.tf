#フロントエンドのバケット
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "${var.project_name}-frontend-bucket"

  tags = {
    Name = "${var.project_name}-frontend-bucket"
  }
  force_destroy = true
}

#QR画像を保存するバケット
resource "aws_s3_bucket" "image_bucket" {
  bucket = "${var.project_name}-images-bucket"

  tags = {
    Name = "${var.project_name}-images-bucket"
  }
  force_destroy = true
}

# S3バケットポリシー
# AWSコンソールではCloudFrontディストリビューション作成時にS3オリジンとOACを指定すると、
# このバケットポリシーは自動で追加されるため、手動で個別に作成する必要はない。
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.image_bucket.id

  # dataソースを使わず、ここで直接JSONを定義・エンコードする
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.image_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.image_cdn.arn
          }
        }
      }
    ]
  })
}

# AWSコンソールではCloudFrontディストリビューション作成時にS3オリジンとOACを指定すると、
# このバケットポリシーは自動で追加されるため、手動で個別に作成する必要はない。
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend_cdn.arn
          }
        }
      }
    ]
  })
}
