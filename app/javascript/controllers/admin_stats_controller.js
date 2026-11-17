import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["prints", "filament", "colors", "error"]
  static values = { data: Object }

  async connect() {
    const connection = Symbol("statistics connection")
    this.connection = connection
    this.charts = []
    this.appearanceChanged = () => this.updateAppearance()
    document.addEventListener("appearance:change", this.appearanceChanged)

    try {
      // This pinned UMD distribution exposes Chart on globalThis when imported.
      await import("chart.js")
      if (this.connection !== connection || !this.element.isConnected) return
      if (!window.Chart) throw new Error("Chart.js did not initialize")

      const data = this.dataValue
      this.charts.push(this.lineChart(this.printsTarget, data.labels, data.prints, "Prints", "#49688e"))
      this.charts.push(this.lineChart(this.filamentTarget, data.labels, data.filament, "Filament (g)", "#07846c"))
      this.charts.push(new window.Chart(this.colorsTarget, {
        type: "doughnut",
        data: {
          labels: data.colorLabels,
          datasets: [{ data: data.colorValues, backgroundColor: data.colors, borderWidth: 2 }]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          animation: this.animation,
          plugins: { legend: { position: "bottom" } }
        }
      }))
      this.updateAppearance()
      this.errorTarget.hidden = true
    } catch (_error) {
      if (this.connection !== connection) return
      this.destroyCharts()
      this.errorTarget.hidden = false
    }
  }

  disconnect() {
    document.removeEventListener("appearance:change", this.appearanceChanged)
    this.clear()
  }

  clear() {
    this.connection = null
    this.destroyCharts()
  }

  destroyCharts() {
    this.charts?.forEach(chart => chart.destroy())
    this.charts = []
  }

  lineChart(canvas, labels, values, label, color) {
    return new window.Chart(canvas, {
      type: "line",
      data: {
        labels,
        datasets: [{ label, data: values, borderColor: color, backgroundColor: color,
          borderWidth: 2, pointRadius: 2, tension: 0.2 }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: this.animation,
        plugins: { legend: { display: false } },
        scales: { y: { beginAtZero: true, ticks: { precision: 0 } } }
      }
    })
  }

  updateAppearance() {
    const styles = getComputedStyle(this.element)
    const color = styles.getPropertyValue("--admin-chart-text").trim() || "#666666"
    const gridColor = styles.getPropertyValue("--admin-chart-grid").trim() || "#d6dde4"
    this.charts?.forEach(chart => {
      chart.options.color = color
      chart.options.plugins.legend.labels.color = color
      Object.values(chart.options.scales || {}).forEach(scale => {
        scale.ticks.color = color
        scale.grid.color = gridColor
        scale.border.color = gridColor
      })
      chart.update("none")
    })
  }

  get animation() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches ? false : undefined
  }
}
