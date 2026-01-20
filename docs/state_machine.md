# Task state machine

States:
- Queued
- Active
- Paused
- Completed
- Failed
- Canceled

Transitions:
- Queued -> Active (scheduler starts)
- Active -> Paused (user pause or loss of connectivity)
- Active -> Completed (all segments complete, checksum OK)
- Active -> Failed (fatal error)
- Paused -> Active (user resume)
- Queued/Paused/Active -> Canceled (user cancel)
- Failed -> Active (user retry)
