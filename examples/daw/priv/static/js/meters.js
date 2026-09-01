/*
 * Level meters, updated without going through the LiveView DOM diff.
 *
 * The engine reports levels ten times a second. Rendering those into the scene
 * would push a diff per node per tick - the editor's own docs put transient,
 * high-frequency state in the browser for exactly this reason, and it also
 * fills the console with diff traffic when LiveView debugging is on.
 *
 * So the server pushes one `levels` event and this hook writes to the DOM
 * directly. Nothing here is authoritative: a lost meter frame is invisible, and
 * the next one arrives 100 ms later.
 */

/** Maps a peak amplitude onto the meter's travel, in percent. */
export function meterWidth(peak) {
  if (!(peak > 0)) return 0

  // A linear meter spends most of its travel showing nothing useful, so map
  // -60..0 dB across the bar instead. Mirrors Daw.Audio.amp_to_db/1.
  const db = 20 * Math.log10(peak)
  return Math.min(100, Math.max(0, ((db + 60) / 60) * 100))
}

export function formatDb(db) {
  return typeof db === "number" && db > -60 ? `${db} dB` : "—"
}

export function applyLevels(root, levels) {
  let applied = 0

  for (const [id, level] of Object.entries(levels || {})) {
    const selector = `[data-meter="${CSS.escape(id)}"]`
    const fill = root.querySelector(`${selector} .daw-node__meter-fill`)
    const readout = root.querySelector(`${selector} .daw-node__db`)

    if (fill) {
      fill.style.width = `${meterWidth(level.peak)}%`
      applied += 1
    }

    if (readout) readout.textContent = formatDb(level.rms_db)
  }

  return applied
}

export function createMetersHook() {
  return {
    mounted() {
      this.handleEvent("levels", ({levels}) => applyLevels(this.el, levels))
    },
  }
}
