resource "aws_ecr_repository" "app" {
  name                 = "1million-testing-nodejs-lab"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

locals {
  app_image_digest_parameter = "/1million/lab/app-image-digest"
  app_image_context          = "${path.module}/../../nodejs"
  app_image_files = [
    ".dockerignore",
    "Dockerfile",
    "package-lock.json",
    "package.json",
    "server.js",
  ]
  app_image_tag = "lab-${sha256(jsonencode({
    files     = { for file in local.app_image_files : file => filesha256("${local.app_image_context}/${file}") }
    publisher = filesha256("${path.module}/../../scripts/publish-image.sh")
  }))}"
}

resource "terraform_data" "app_image" {
  triggers_replace = local.app_image_tag

  lifecycle {
    replace_triggered_by = [aws_ecr_repository.app]
  }

  provisioner "local-exec" {
    command     = "bash scripts/publish-image.sh"
    working_dir = abspath("${path.module}/../..")

    environment = {
      APP_AWS_ACCOUNT_ID         = var.aws_account_id
      APP_AWS_REGION             = var.aws_region
      APP_ECR_REPOSITORY_URL     = aws_ecr_repository.app.repository_url
      APP_IMAGE_DIGEST_PARAMETER = local.app_image_digest_parameter
      APP_IMAGE_TAG              = local.app_image_tag
    }
  }
}

data "aws_ssm_parameter" "app_image_digest" {
  name            = local.app_image_digest_parameter
  with_decryption = false

  depends_on = [terraform_data.app_image]

  lifecycle {
    postcondition {
      condition     = can(regex("^sha256:[0-9a-f]{64}$", self.value))
      error_message = "The image digest parameter must contain sha256: followed by 64 lowercase hexadecimal characters."
    }
  }
}

data "aws_ecr_image" "app" {
  registry_id     = var.aws_account_id
  repository_name = aws_ecr_repository.app.name
  image_digest    = data.aws_ssm_parameter.app_image_digest.value
}
