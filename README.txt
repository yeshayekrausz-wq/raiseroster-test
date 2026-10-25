Planner bookmark tabs and loading indicator

Upload the motivation folder and sw.js to the same GitHub paths, preserving the other existing files. Refresh with Ctrl+Shift+R. No additional SQL is required for this visual update.

Six connected bookmark/arrow tabs highlight the selected step and remain keyboard accessible. Smaller screens wrap them into rows. During calculations, saving and card generation, a spinning activity indicator and a message explain that large jobs may take a few minutes. The existing elapsed-time text remains. Preview waits up to two minutes before offering a retry without losing inputs; no artificial delay is added. Reduced-motion preferences display a static activity indicator.

Checked in Chromium: normal preview, loading visibility, disabled controls while busy, two-minute timeout, spinner removal, retained inputs, retry, generation and real admin-shell navigation. No live deployment performed.
