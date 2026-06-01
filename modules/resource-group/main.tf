resource "azurerm_resource_group" "this" {
  name     = "${var.component}-${var.org}-${var.project}-${var.env}"
  location = var.location

  tags = merge(
    {
      project    = var.project
      env        = var.env
      managed_by = "terraform"
      owner      = "indentwork"
    },
    var.tags
  )
}
