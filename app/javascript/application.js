import "@hotwired/turbo-rails"
import { StreamActions, visit } from "@hotwired/turbo"
import "controllers"
import Highcharts from "highcharts"
import Chartkick from "chartkick"
import "lexxy"

window.Highcharts = Highcharts
Chartkick.use(Highcharts)
Highcharts.setOptions({ accessibility: { enabled: false } })

// Custom turbo stream action: navigate to a URL (used for escaping turbo frames)
StreamActions.navigate = function () {
  visit(this.getAttribute("target"))
}
