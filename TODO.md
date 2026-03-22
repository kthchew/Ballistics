Pool Logic
- Add more scratch rules (not hitting a rail)
- Improve model of pool table (add bottom to pockets)

* Classical AI
- Pick pocket
- Add collision check to placing ball
- Add random shots if no potting and non-potting non-scratching shot is found
- Select shot based on clearance and loss of momentum
- Select power based on loss of momentum
- Bank off walls
- Old bug that I forgot about: collision of shapecast not found if there is a ball close to the origin. Like cue ball thinks it can hit through object ball if it's close?
- Why are ball positions y != 2.85 (ball radius)
