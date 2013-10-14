Flow Free Solver
================

Solves [Flow](https://itunes.apple.com/us/app/flow-free/id526641427) [Free](https://play.google.com/store/apps/details?id=com.bigduckgames.flow) puzzles.

![animation](https://raw.github.com/idiomatic/flowfree/master/animation.gif)

Getting the Puzzles
-------------------

Do so at your own risk.

### Apple Ecosystem

1. download the .ipa file with iTunes

2. extract puzzles

        unzip -e ~/Music/iTunes/iTunes\ Media/Mobile\ Applications/Flow\ Free\ 1.7.ipa Payload/Flow.app/levelpack\*.txt

### Google Ecosystem

1. download the .apk file

2. extract puzzles

        unzip -e Flow\ Free\ v2.4.apk assets/levelpack\*.txt


Data Structure
--------------

A tree of partially complete puzzle states.  Each state has tile
assignment (initially BLANK or WALL), a list of partial trace ends,
and the number of vacant tiles.

The puzzle has a stack of untested alternatives and a list of
completed boards.


Algorithm
---------

1. for each segment endpoint, repeatedly look for mandatory advancement
2. check if it creates undesirable conditions
3. pick a segment endpoint with the fewest number of alternatives
4. try each alternative


Tricks
------

* Patterns are translated into a JavaScript decision tree and compiled
* Mandatory patterns promptly force into undesirable conditions rather
  than test for the potential
* Puzzle and Tiles share attributes for ease of root Tiles creation
* Tiles are lightweight to avoid overhead setting up each alternative
* Display refresh is periodic and not a bottleneck to alternative traversal
* Array splicing avoided by recycling array position
* Board is represented as an one-dimensional array with walls tile assigments
* Mandatory segment end extension prefers just-moved endpoint (does not
  increment the index)
* Guesses recycle the existing Tiles to avoid one clone
* Pattern results are tile offsets and are lazily used to optimize
  multiple guesses

