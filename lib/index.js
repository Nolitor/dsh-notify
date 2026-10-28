/**
 * DSH Notify Web — Host half.
 *
 * This entry exists only so the DSH Loader can register the package. The
 * notification implementation runs entirely in the browser (`./client.js`).
 * It intentionally has no services, no filesystem access, no network listener,
 * and no IPC.
 */
export const name = 'dsh-notify-web'

export function apply() {
  // Intentionally empty: the browser half owns all behavior.
}
