resource "aws_cloudwatch_log_group" "app" {
  for_each = {
    nodejs       = "/1million-lab/nodejs"
    nginx_access = "/1million-lab/nginx/access"
    nginx_error  = "/1million-lab/nginx/error"
    bootstrap    = "/1million-lab/bootstrap"
  }

  name              = each.value
  retention_in_days = 7
}
