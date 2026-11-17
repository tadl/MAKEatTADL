import { Controller } from "@hotwired/stimulus"

let libraryPromise

function loadScript(src, integrity) {
  return new Promise((resolve, reject) => {
    const script = document.createElement("script")
    const timeout = setTimeout(() => reject(new Error("Preview library timed out")), 20000)
    script.src = src
    script.integrity = integrity
    script.crossOrigin = "anonymous"
    script.onload = () => { clearTimeout(timeout); resolve() }
    script.onerror = () => { clearTimeout(timeout); script.remove(); reject(new Error("Preview library unavailable")) }
    document.head.appendChild(script)
  })
}

function loadLibraries() {
  if (!libraryPromise) {
    libraryPromise = (async () => {
      if (!window.THREE) await loadScript("https://cdnjs.cloudflare.com/ajax/libs/three.js/r134/three.min.js", "sha384-9EQoUIJYrv09/oYhSxnw1VpLcfPw3BM9dE7+D/3wGUPeLLa7F9Z6OAoD+i/M6FK9")
      if (!window.THREE.STLLoader) await loadScript("https://cdn.jsdelivr.net/npm/three@0.134.0/examples/js/loaders/STLLoader.js", "sha384-QF8EmP6pyNE+i7WmcltzC4ddzFVKDxfn5WD5gXyKTSE4SCw0R25TI+q0LUlnf7tq")
      if (!window.THREE.OrbitControls) await loadScript("https://cdn.jsdelivr.net/npm/three@0.134.0/examples/js/controls/OrbitControls.js", "sha384-aizNATw2wQruqMN04RDyo9uvO1pHrWXvhHJ8u9R8f5ws1mnKzmVJQUYeBxByY7Gs")
      return window.THREE
    })().catch(error => { libraryPromise = null; throw error })
  }
  return libraryPromise
}

export default class extends Controller {
  static targets = ["canvas", "status"]
  static values = { url: String }

  connect() {
    this.disconnected = false
    if (this.element.open) this.toggle()
  }

  disconnect() {
    this.disconnected = true
    this.abortController?.abort()
    this.resizeObserver?.disconnect()
    this.controls?.dispose()
    this.geometry?.dispose()
    this.material?.dispose()
    this.renderer?.dispose()
    this.canvasTarget.replaceChildren()
    this.renderer = null
    this.loading = false
  }

  async toggle() {
    if (!this.element.open || this.renderer || this.loading) return
    this.loading = true
    this.statusTarget.textContent = "Loading 3D preview…"
    try {
      const THREE = await loadLibraries()
      if (this.disconnected) return
      this.abortController = new AbortController()
      const response = await fetch(this.urlValue, { signal: this.abortController.signal })
      if (!response.ok) throw new Error("Model file unavailable")
      const data = await response.arrayBuffer()
      if (this.disconnected) return
      this.geometry = new THREE.STLLoader().parse(data)
      this.geometry.center()
      this.geometry.computeBoundingBox()
      this.geometry.computeVertexNormals()
      this.scene = new THREE.Scene()
      this.scene.background = new THREE.Color(0xf8fafc)
      this.material = new THREE.MeshNormalMaterial({ side: THREE.DoubleSide })
      this.scene.add(new THREE.Mesh(this.geometry, this.material))
      this.camera = new THREE.PerspectiveCamera(45, 1, 0.01, 100000)
      const size = this.geometry.boundingBox.getSize(new THREE.Vector3())
      const distance = Math.max(size.x, size.y, size.z, 1) * 2.2
      this.camera.position.set(distance, distance * 0.7, distance)
      this.initialPosition = this.camera.position.clone()
      this.camera.near = Math.max(distance / 1000, 0.01)
      this.camera.far = distance * 100
      this.renderer = new THREE.WebGLRenderer({ antialias: true })
      this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2))
      this.renderer.domElement.setAttribute("aria-label", "3D model. Use the zoom and reset buttons, or drag to rotate.")
      this.canvasTarget.appendChild(this.renderer.domElement)
      this.controls = new THREE.OrbitControls(this.camera, this.renderer.domElement)
      this.controls.addEventListener("change", () => this.render())
      this.controls.update()
      this.addButtons()
      this.resizeObserver = new ResizeObserver(() => this.resize())
      this.resizeObserver.observe(this.canvasTarget)
      this.resize()
      this.statusTarget.textContent = "Drag to rotate; scroll to zoom."
    } catch (error) {
      if (!this.disconnected && error.name !== "AbortError") {
        this.statusTarget.textContent = "Preview unavailable. You can still download the model file above."
      }
    } finally {
      this.loading = false
    }
  }

  addButtons() {
    const bar = document.createElement("div")
    bar.className = "absolute right-3 top-3 flex gap-1"
    const actions = [
      ["+", "Zoom in", () => this.zoom(1.25)],
      ["−", "Zoom out", () => this.zoom(0.8)],
      ["Reset", "Reset view", () => { this.camera.position.copy(this.initialPosition); this.camera.zoom = 1; this.controls.target.set(0, 0, 0); this.camera.updateProjectionMatrix(); this.controls.update(); this.render() }]
    ]
    actions.forEach(([label, title, action]) => {
      const button = document.createElement("button")
      button.type = "button"
      button.className = "admin-btn admin-btn-secondary"
      button.textContent = label
      button.setAttribute("aria-label", title)
      button.addEventListener("click", action)
      bar.appendChild(button)
    })
    this.canvasTarget.appendChild(bar)
  }

  zoom(multiplier) {
    this.camera.zoom = Math.max(0.2, Math.min(8, this.camera.zoom * multiplier))
    this.camera.updateProjectionMatrix()
    this.render()
  }

  resize() {
    if (!this.renderer) return
    const width = this.canvasTarget.clientWidth || 500
    const height = this.canvasTarget.clientHeight || 320
    this.camera.aspect = width / height
    this.camera.updateProjectionMatrix()
    this.renderer.setSize(width, height)
    this.render()
  }

  render() {
    if (this.renderer && !this.disconnected) this.renderer.render(this.scene, this.camera)
  }
}
