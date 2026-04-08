# Ballistics

![diagram](./assets/docs/arch-diagram.svg)

## Collision Layers

1 << 0 == 1: walls and balls
1 << 1 == 2: floor, turned off when in hole
1 << 2 == 4: shapecast for aimline and AI
