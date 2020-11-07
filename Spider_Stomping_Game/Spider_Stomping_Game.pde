/*------------------------------------------------------------------------------

Spider Stomping Driveway Game

Copyright 2020 Kyle Maas <kylemaasdev@gmail.com>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

------------------------------------------------------------------------------*/

import SimpleOpenNI.*;
import processing.sound.*;

// Originally designed for Processing sound library 2.0.2.  Updated to 2.2.3 on 2020-10-31.

SimpleOpenNI kinect;
int depthWidth = 640;
int depthHeight = 480;

boolean calibrated = false;
int calibrationLastStepTime = 0;
int calibrationAutoAdvanceInterval = 10000;

PVector floorTopLeft3D = new PVector();
PVector floorTopRight3D = new PVector();
PVector floorBottomLeft3D = new PVector();
PVector floorBottomRight3D = new PVector();

PVector floorTopLeft2D = new PVector();
PVector floorTopRight2D = new PVector();
PVector floorBottomLeft2D = new PVector();
PVector floorBottomRight2D = new PVector();

PVector floorBasisX = new PVector();
PVector floorBasisY = new PVector();

PVector lastLeftFoot = new PVector();
PVector lastRightFoot = new PVector();
PVector leftFoot2D = new PVector();
PVector rightFoot2D = new PVector();
Object feet2DLock = new Object();
PVector[] feet2D;
int userLastSeenTime = 0;
float rotateGameElements = 90; //-90;

float confidenceThreshold = 0.5;

// https://openclipart.org/detail/85327/halloween-spider-web-icon
PImage imageSpiderWeb;
// https://openclipart.org/detail/33763/architetto-ragnetto-incazzato
PImage imageSpider;
PImage imageSpiderSplat;
// https://openclipart.org/detail/236010/grey-cloud-1
PImage imagePoof;
// https://openclipart.org/detail/173421/stopwatch
PImage imageTimer;

// Cackle sound.
// https://freesound.org/people/AntumDeluge/sounds/417826/
SoundFile soundSpiderStart1;
// Kung Fu yell.
// https://freesound.org/people/oldedgar/sounds/97977/
SoundFile soundSpiderStart2;
// Yee-haw! sound.
// https://freesound.org/people/shawshank73/sounds/102437/
SoundFile soundSpiderStart3;
// Yoo-hoo sound.
// https://freesound.org/people/sandyrb/sounds/86223/
SoundFile soundSpiderStart4;
// Squish sound.
// https://freesound.org/people/Cheddrock/sounds/412919/
SoundFile soundSquish1;
SoundFile soundSquish2;
SoundFile soundSquish3;
// Splat sound.
// https://freesound.org/people/MattLeschuck/sounds/402402/
// Poof sound.
// https://freesound.org/people/ryansitz/sounds/387834/
SoundFile soundPoof;
// Start bugle.
// https://freesound.org/people/craigsmith/sounds/438633/
SoundFile soundGameStart;
// End gong.
// https://freesound.org/people/GowlerMusic/sounds/266566/
SoundFile soundGameEnd;

int standingInCenterCircleStartTime = 0;
int gameStartedAtTime = 0;
float startCircleSize = 0.3;
float timePerGame = 90000;
int spidersStomped = 0;
// For figuring out the state transition to game over for playing the end sound.
boolean playedGameOverSound = false;

boolean disableSound = false;

class Spider {
  public float x = 0;
  public float y = 0;
  public float trajectoryX = 0;
  public float trajectoryY = 0;
  public int aliveAtTime = 0;
  public int deadAtTime = 0;
  public float rotation = 0;
  public boolean playedStartSound = false;
  public boolean playedPoofSound = false;
}

Spider[] spiders;

SecondWindow displayWindow;

void settings() {
  //fullScreen(P2D);
  size(640, 480);
}

void setup() {
  kinect = new SimpleOpenNI(this);
  kinect.enableDepth();
  kinect.enableUser();
  fill(255, 0, 0);
  kinect.setMirror(true);

  imageSpiderWeb = loadImage("../Graphics/Halloween-Spider-Web-Icon.png");
  imageSpider = loadImage("../Graphics/ragnetto-incazzato-arch-04r.png");
  imageSpiderSplat = loadImage("../Graphics/ragnetto-incazzato-arch-04r-splat.png");
  imagePoof = loadImage("../Graphics/grey-cloud-1-poof.png");
  imageTimer = loadImage("../Graphics/1354075811-square.png");
  
  if(!disableSound) {
    soundSpiderStart1 = new SoundFile(this, "../Sounds/417826__antumdeluge__witch-cackle-normalized.mp3");
    soundSpiderStart2 = new SoundFile(this, "../Sounds/97977__oldedgar__kung-fu-yell-sped-up-normalized.mp3");
    soundSpiderStart3 = new SoundFile(this, "../Sounds/102437__shawshank73__scottstoked-yeehaw-sped-up-downpitched-normalized.mp3");
    soundSpiderStart4 = new SoundFile(this, "../Sounds/86223__sandyrb__yoo-hoo-01-sped-up-normalized.wav");
    soundSquish1 = new SoundFile(this, "../Sounds/412919__cheddrock__squishes-2-fast-normalized.mp3");
    soundSquish2 = new SoundFile(this, "../Sounds/412919__cheddrock__squishes-4-fast-normalized.mp3");
    soundSquish3 = new SoundFile(this, "../Sounds/412919__cheddrock__squishes-5-normalized.mp3");
    soundPoof = new SoundFile(this, "../Sounds/387834__ryansitz__poof-normalized.wav");
    soundGameStart = new SoundFile(this, "../Sounds/438633__craigsmith__g39-16-bugle-call-normalized.mp3");
    soundGameEnd = new SoundFile(this, "../Sounds/266566__gowlermusic__gong-hit-fade-normalized.mp3");
  }

  displayWindow = new SecondWindow(this, "RunWindow");
}

void updateFeet() {
  IntVector userList = new IntVector();
  kinect.getUsers(userList);

  synchronized(feet2DLock) {
    feet2D = new PVector[0];
    for(int u = 0; u < userList.size(); ++u) {
      int userId = userList.get(u);
      //If we detect one user we have to draw it
      if ( kinect.isTrackingSkeleton(userId)) {
        // Update the left and right foot positions.
        PVector leftJoint = new PVector();
        float confidence = kinect.getJointPositionSkeleton(userId, SimpleOpenNI.SKEL_LEFT_FOOT, leftJoint);
        if (confidence >= confidenceThreshold) {
          //println("Found left foot");
          lastLeftFoot = leftJoint;
        }
        PVector rightJoint = new PVector();
        confidence = kinect.getJointPositionSkeleton(userId, SimpleOpenNI.SKEL_RIGHT_FOOT, rightJoint);
        if (confidence >= confidenceThreshold) {
          //println("Found right foot");
          lastRightFoot = rightJoint;
        }
  
        if (calibrated) {
          translate3DPointToUV(lastLeftFoot, leftFoot2D);
          translate3DPointToUV(lastRightFoot, rightFoot2D);
          PVector[] newFeet2D = new PVector[feet2D.length + 2];
          for(int f = 0; f < feet2D.length; ++f) {
            newFeet2D[f] = feet2D[f];
          }
          newFeet2D[newFeet2D.length - 2] = new PVector(leftFoot2D.x, leftFoot2D.y);
          newFeet2D[newFeet2D.length - 1] = new PVector(rightFoot2D.x, rightFoot2D.y);
          feet2D = newFeet2D;
          userLastSeenTime = millis();
          //println("Left foot position in UV space: " + leftFoot2D.x + ", " + leftFoot2D.y);
        }
  
        //Draw the skeleton user
        drawSkeleton(userId);
  
        // Since we're still tracking the user, see if we need to advance calibration.
        if (millis() - calibrationLastStepTime >= calibrationAutoAdvanceInterval) {
          calibrateNextStep();
          break;
        }
      }
    }
  }
}

void draw() {
  kinect.update();

  PImage depthImage = kinect.depthImage();
  depthWidth = depthImage.width;
  depthHeight = depthImage.height;
  image(depthImage, 0, 0, width, height);
  
  updateFeet();

  if (calibrated) {
    drawFloor();
  }
}

float edgeSpawnX(int edge) {
  switch(edge) {
    case 0:
      return random(0.25, 0.75);
    case 1:
      return 1.1;
    case 2:
      return random(0.25, 0.75);
    case 3:
    default:
      return -0.1;
  }
}

float edgeSpawnY(int edge) {
  switch(edge) {
    case 0:
      return -0.1;
    case 1:
      return random(0.25, 0.75);
    case 2:
      return 1.1;
    case 3:
    default:
      return random(0.25, 0.75);
  }
}

void spawnSpider(Spider spider, int edge) {
  if(edge < 0) {
    edge = (int)random(0, 4);
  }
  spider.x = edgeSpawnX(edge);
  spider.y = edgeSpawnY(edge);
  
  int otherEdge = (int)random(0, 4);
  if(otherEdge == edge) {
    otherEdge = (edge + 2) % 4;
  }
  
  spider.trajectoryX = edgeSpawnX(otherEdge);
  spider.trajectoryY = edgeSpawnY(otherEdge);
  //println("From/to: " + edge + "(" + spider.x + "," + spider.y + ") - " + otherEdge + "(" + spider.trajectoryX + "," + spider.trajectoryY + ")");
  spider.trajectoryX -= spider.x;
  spider.trajectoryY -= spider.y;
  float vectorLength = sqrt(spider.trajectoryX * spider.trajectoryX + spider.trajectoryY * spider.trajectoryY);
  spider.trajectoryX /= vectorLength;
  spider.trajectoryY /= vectorLength;
  //println("Trajectory: (" + spider.trajectoryX + "," + spider.trajectoryY + ")"); 
  spider.aliveAtTime = millis();
  spider.deadAtTime = 0;
  spider.rotation = rotateGameElements;
  spider.playedPoofSound = false;
  spider.playedStartSound = false;
}

void drawGame(PApplet drawTo, int drawWidth, int drawHeight) {
  // Draw the play field.
  drawTo.background(100);
  drawTo.imageMode(CORNER);
  drawTo.image(imageSpiderWeb, 0, 0, drawWidth, drawHeight);
  
  // See if the game has started yet.  If it hasn't, draw a "stand here to start" circle.
  if(gameStartedAtTime < 1) {
    // Game hasn't started yet.
    
    // See if all feet are within the circle.  If they are, start the timer.
    int circleSize = (int)(startCircleSize * (float)drawWidth);
    int withinCircle = 0;
    if(feet2D.length < 1)
    {
      standingInCenterCircleStartTime = 0;
    } else {
      float circleWidthInUVSpace = (float)circleSize / (float)drawWidth;
      float circleHeightInUVSpace = (float)circleSize / (float)drawHeight;
      //println("Circle size in UV space: " + circleWidthInUVSpace + ", " + circleHeightInUVSpace);
      // Assume they're in the circle unless found to be otherwise.
      withinCircle = 0;
      synchronized(feet2DLock) {
        for(int f = 0; f < feet2D.length; ++f)
        {
          //println("Foot position: " + feet2D[f].x + ", " + feet2D[f].y);
          if(feet2D[f].x >= 0.5 - circleWidthInUVSpace / 2 && feet2D[f].x <= 0.5 + circleWidthInUVSpace / 2) {
            if(feet2D[f].y >= 0.5 - circleHeightInUVSpace / 2 && feet2D[f].y <= 0.5 + circleHeightInUVSpace / 2) {
              ++withinCircle;
            }
          }
        }
      }
      if(withinCircle >= 2) {
        if(standingInCenterCircleStartTime < 1) {
          standingInCenterCircleStartTime = millis();
        } else if(millis() - standingInCenterCircleStartTime >= 3000) {
          // Start game.
          gameStartedAtTime = millis();
          spidersStomped = 0;
          
          // Add one spider somewhere.
          spiders = new Spider[1];
          Spider firstSpider = new Spider();
          // Put the first spider up near the "top" of the screen so players can see it.
          if(rotateGameElements >= -45 && rotateGameElements < 45) {
            spawnSpider(firstSpider, 0);
          } else if(rotateGameElements >= 45 && rotateGameElements <= 135) {
            spawnSpider(firstSpider, 1);
          } else if(rotateGameElements < -45 && rotateGameElements >= -135) {
            spawnSpider(firstSpider, 3);
          } else {
            spawnSpider(firstSpider, 2);
          }
          firstSpider.rotation = rotateGameElements;
          firstSpider.trajectoryX = (0.5 - firstSpider.x);
          firstSpider.trajectoryY = (0.5 - firstSpider.y);
          // Normalize.
          float trajectoryLength = sqrt(firstSpider.trajectoryX * firstSpider.trajectoryX + firstSpider.trajectoryY * firstSpider.trajectoryY);
          firstSpider.trajectoryX /= trajectoryLength;
          firstSpider.trajectoryY /= trajectoryLength;
          // Don't play a start sound for the first spider.
          firstSpider.playedStartSound = true;
          spiders[0] = firstSpider;
          
          // Play the starting sound.
          if(!disableSound) {
            soundGameStart.play();
          }
          playedGameOverSound = false;
        }
      }
    }
    
    // Now that we know whether the player is in the circle, draw a "stand here to start" circle.
    drawTo.pushMatrix();
    drawTo.translate(drawWidth / 2, drawHeight / 2);
    drawTo.rotate(radians(rotateGameElements));
    drawTo.rectMode(CENTER);
    if(withinCircle >= 2) {
      drawTo.fill(0, 200, 0);
      drawTo.stroke(0, 255, 0);
    } else {
      drawTo.fill(0, 170, 0);
      drawTo.stroke(0, 220, 0);
    }
    drawTo.strokeWeight(drawWidth / 32);
    drawTo.ellipseMode(CENTER);
    drawTo.ellipse(0, 0, circleSize, circleSize);
    drawTo.textSize(circleSize / 8);
    drawTo.fill(255, 255, 255);
    drawTo.textAlign(CENTER, CENTER);
    String gameStartText = "Stand here to start";
    if(withinCircle >= 2) {
      gameStartText = "Starting game...";
    }
    drawTo.text(gameStartText, 0, 0, circleSize * 0.75, circleSize * 0.75);
    drawTo.popMatrix();
  } else if(millis() - gameStartedAtTime <= timePerGame) {
    // Game has started.
    
    // Move the spiders.
    float startDivisor = 150;
    float divisorDropPerSpider = 5;
    float minDivisor = 80;
    float speedMultiplier = 1.0 / max(minDivisor, startDivisor - spidersStomped * divisorDropPerSpider);
    for(int s = 0; s < spiders.length; ++s)
    {
      spiders[s].x += spiders[s].trajectoryX * speedMultiplier;
      spiders[s].y += spiders[s].trajectoryY * speedMultiplier;
    }
    
    // See if any spiders have left the play field, and if they have, respawn.
    for(int s = 0; s < spiders.length; ++s)
    {
      if(spiders[s].x > 1.2 || spiders[s].x < -0.2 || spiders[s].y > 1.2 || spiders[s].y < -0.2) {
        spawnSpider(spiders[s], -1);
      }
    }
    
    // See if the player has stepped on any spiders.
    float spiderSquishThreshold = 0.1875;
    for(int s = 0; s < spiders.length; ++s)
    {
      if(spiders[s].deadAtTime < 1) {
        float minDistanceToFootSquared = 1000;
        synchronized(feet2DLock) {
          for(int f = 0; f < feet2D.length; ++f) {
            float distanceX = (feet2D[f].x - spiders[s].x);
            float distanceY = (feet2D[f].y - spiders[s].y);
            minDistanceToFootSquared = min(minDistanceToFootSquared, (distanceX * distanceX + distanceY * distanceY));
          }
        }
        if(minDistanceToFootSquared <= (spiderSquishThreshold * spiderSquishThreshold)) {
          spiders[s].trajectoryX = 0;
          spiders[s].trajectoryY = 0;
          spiders[s].deadAtTime = millis();
          ++spidersStomped;
          
          // Play a random squish sound.
          if(!disableSound) {
            switch((int)random(0, 3)) {
              case 0:
                soundSquish1.play();
                break;
              case 1:
                soundSquish2.play();
                break;
              default:
                soundSquish3.play();
            }
          }
        } else {
          // Far from the player - let's see if we need to play a start sound.
          if(!spiders[s].playedStartSound && millis() - spiders[s].aliveAtTime > 1000) {
            if(!disableSound) {
              switch((int)random(0, 6)) {
                case 0:
                  soundSpiderStart1.play();
                  break;
                case 1:
                  soundSpiderStart2.play();
                  break;
                case 2:
                  soundSpiderStart3.play();
                  break;
                case 3:
                  soundSpiderStart4.play();
                  break;
                default:
                  // Not all spiders play a sound, so as not to be too obnoxious.  Change random above if you want more or less silence.
              }
            }
            spiders[s].playedStartSound = true;
          }
        }
      }
    }
    
    // See if there are any spiders left alive.  If there are not, spawn more, up to 5.
    boolean anySpidersAlive = false;
    for(int s = 0; s < spiders.length; ++s)
    {
      anySpidersAlive |= (spiders[s].deadAtTime < 1);
    }
    boolean increaseSpiderSize = (!anySpidersAlive && spiders.length < 5);
    if(spiders.length < spidersStomped / 10) {
      increaseSpiderSize = true;
    }
    if(spiders.length >= 12) {
      increaseSpiderSize = false;
    }
    if(increaseSpiderSize) {
      Spider[] newSpiders = new Spider[spiders.length + 1];
      for(int s = 0; s < spiders.length; ++s) {
        newSpiders[s] = spiders[s];
      }
      newSpiders[newSpiders.length - 1] = new Spider();
      spawnSpider(newSpiders[newSpiders.length - 1], -1);
      spiders = newSpiders;
    }
    
    // Display the spiders.
    for(int s = 0; s < spiders.length; ++s)
    {
      drawTo.pushMatrix();
      drawTo.translate(spiders[s].x * drawWidth, spiders[s].y * drawHeight);
      drawTo.rotate(radians(spiders[s].rotation));
      drawTo.imageMode(CENTER);
      if(spiders[s].deadAtTime < 1) {
        // Wiggle them back and forth a little bit so they don't look like they're just floating.
        drawTo.rotate(sin((float)(millis() - spiders[s].aliveAtTime) / 500.0 * PI) * radians(10));
        drawTo.image(imageSpider, 0, 0, drawWidth / 8, drawWidth / 8);
      } else {
        // Dead spider.
        if(millis() - spiders[s].deadAtTime < 750) {
          drawTo.image(imageSpiderSplat, 0, 0, drawWidth / 8, drawWidth / 8);
        } else if(millis() - spiders[s].deadAtTime < 1500) {
          // Display "poof" cloud.
          drawTo.image(imagePoof, 0, 0, drawWidth / 8, drawWidth / 8);
          
          // Play "poof" sound if needed.
          if(!spiders[s].playedPoofSound) {
            if(!disableSound) {
              soundPoof.play();
            }
            spiders[s].playedPoofSound = true;
          }
        } else {
          // Spider is done being "poofed".
          // Respawn spider.
          spawnSpider(spiders[s], -1);
        }
      }
      drawTo.popMatrix();
    }
    
    // Display the time and number of squished spiders.
    int elapsedTime = millis() - gameStartedAtTime;
    int secondsLeft = ceil((float)(timePerGame - elapsedTime) / 1000.0);
    String timeDisplay = (secondsLeft / 60) + ":" + (secondsLeft % 60 < 10 ? "0" : "") + (secondsLeft % 60);
    drawTo.pushMatrix();
    drawTo.translate(drawWidth / 2, drawHeight / 2);
    drawTo.rotate(radians(rotateGameElements));
    drawTo.rectMode(CENTER);
    drawTo.imageMode(CORNER);
    drawTo.fill(255, 255, 255);
    float textSize = drawWidth / 12;
    drawTo.textSize(textSize);
    if((rotateGameElements <= -45 && rotateGameElements >= -135) || (rotateGameElements > 45 && rotateGameElements <= 135)) {
      drawTo.image(imageTimer, drawHeight / 2 - textSize, -drawWidth / 2, textSize, textSize);
      drawTo.textAlign(RIGHT, TOP);
      drawTo.text(timeDisplay, drawHeight / 2 - textSize, -drawWidth / 2);
      
      drawTo.image(imageSpiderSplat, -drawHeight / 2, -drawWidth / 2, textSize, textSize);
      drawTo.textAlign(LEFT, TOP);
      drawTo.text(spidersStomped, -drawHeight / 2 + textSize, -drawWidth / 2);
    } else {
      drawTo.image(imageTimer, drawWidth / 2 - textSize, -drawHeight / 2, textSize, textSize);
      drawTo.textAlign(RIGHT, TOP);
      drawTo.text(timeDisplay, drawWidth / 2 - textSize, -drawHeight / 2);
      
      drawTo.image(imageSpiderSplat, -drawWidth / 2, -drawHeight / 2, textSize, textSize);
      drawTo.textAlign(LEFT, TOP);
      drawTo.text(spidersStomped, -drawWidth / 2 + textSize, -drawHeight / 2);
    }
    drawTo.popMatrix();
  } else {
    // Game over.
    int displayGameOverFor = 10000;
    
    if(!playedGameOverSound) {
      if(!disableSound) {
        soundGameEnd.play();
      }
      playedGameOverSound = true;
    }
    
    drawTo.pushMatrix();
    drawTo.translate(drawWidth / 2, drawHeight / 2);
    drawTo.rotate(radians(rotateGameElements));
    drawTo.rectMode(CENTER);
    drawTo.fill(255, 255, 255);
    float textSize = drawWidth / 8;
    drawTo.textSize(textSize);
    drawTo.image(imageSpiderSplat, -textSize / 2, -textSize * 2, textSize, textSize); 
    String gameOverText = "You win!";
    if(spidersStomped < 1) {
      gameOverText = "Try again?";
    }
    drawTo.textAlign(CENTER, BOTTOM);
    drawTo.text(gameOverText, 0, 0);
    drawTo.textSize(textSize / 2);
    drawTo.textAlign(CENTER, TOP);
    drawTo.text(spidersStomped + " Spiders", 0, 0);
    drawTo.popMatrix();
    
    if(millis() - gameStartedAtTime >= timePerGame + displayGameOverFor) {
      // Reset game.
      standingInCenterCircleStartTime = 0;
      gameStartedAtTime = 0;
    }
  }
  
  // Draw the detected foot positions.
  drawTo.noFill();
  drawTo.strokeWeight(drawWidth / 32);
  drawTo.stroke(255, 255, 0, 100);
  drawTo.ellipseMode(CENTER);
  synchronized(feet2DLock) {
    for (int i = 0; i < feet2D.length; ++i) {
      drawTo.ellipse(feet2D[i].x * drawWidth, feet2D[i].y * drawHeight, drawWidth / 32, drawWidth / 32);
    }
  }
}

void keyPressed() {
  if (!calibrated) {
    calibrateNextStep();
  }
}

void calibrateNextStep() {
  // See how much data we've generated.
  if (floorTopLeft3D.x == 0 && floorTopLeft3D.y == 0) {
    //println("Setting point top left");
    floorTopLeft3D = new PVector((lastLeftFoot.x + lastRightFoot.x) / 2, (lastLeftFoot.y + lastRightFoot.y) / 2, (lastLeftFoot.z + lastRightFoot.z) / 2);
  } else if (floorTopRight3D.x == 0 && floorTopRight3D.y == 0) {
    //println("Setting point top right");
    floorTopRight3D = new PVector((lastLeftFoot.x + lastRightFoot.x) / 2, (lastLeftFoot.y + lastRightFoot.y) / 2, (lastLeftFoot.z + lastRightFoot.z) / 2);
  } else if (floorBottomRight3D.x == 0 && floorBottomRight3D.y == 0) {
    //println("Setting point bottom right");
    floorBottomRight3D = new PVector((lastLeftFoot.x + lastRightFoot.x) / 2, (lastLeftFoot.y + lastRightFoot.y) / 2, (lastLeftFoot.z + lastRightFoot.z) / 2);
  } else if (floorBottomLeft3D.x == 0 && floorBottomLeft3D.y == 0) {
    //println("Setting point bottom left");
    floorBottomLeft3D = new PVector((lastLeftFoot.x + lastRightFoot.x) / 2, (lastLeftFoot.y + lastRightFoot.y) / 2, (lastLeftFoot.z + lastRightFoot.z) / 2);
    //println("Setting up floor basis");
    // Figure out the floor basis for transforming to 2D.
    floorBasisX = normalizeVector(new PVector(floorTopRight3D.x - floorTopLeft3D.x, floorTopRight3D.y - floorTopLeft3D.y, floorTopRight3D.z - floorTopLeft3D.z));
    //println("Floor basis X: (" + floorBasisX.x + ", " + floorBasisX.y + ", " + floorBasisX.z + ")");
    floorBasisY = normalizeVector(new PVector(floorBottomLeft3D.x - floorTopLeft3D.x, floorBottomLeft3D.y - floorTopLeft3D.y, floorBottomLeft3D.z - floorTopLeft3D.z));
    PVector floorBasisZ = normalizeVector(crossProduct(floorBasisY, floorBasisX, new PVector()));
    //println("Floor basis Z: (" + floorBasisZ.x + ", " + floorBasisZ.y + ", " + floorBasisZ.z + ")");

    // Now that we have an X and a Z (up off the floor), we can recalculate our Y vector so it's perpendicular to X.
    floorBasisY = normalizeVector(crossProduct(floorBasisX, floorBasisZ, floorBasisY));
    //println("Floor basis Y: (" + floorBasisY.x + ", " + floorBasisY.y + ", " + floorBasisY.z + ")");

    // Project each of the 3D corners into 2D space.
    //project3DTo2D(floorTopLeft3D, floorTopLeft2D);
    floorTopLeft2D.x = 0;
    floorTopLeft2D.y = 0;
    project3DTo2D(new PVector(floorTopRight3D.x - floorTopLeft3D.x, floorTopRight3D.y - floorTopLeft3D.y, floorTopRight3D.z - floorTopLeft3D.z), floorTopRight2D);
    project3DTo2D(new PVector(floorBottomLeft3D.x - floorTopLeft3D.x, floorBottomLeft3D.y - floorTopLeft3D.y, floorBottomLeft3D.z - floorTopLeft3D.z), floorBottomLeft2D);
    project3DTo2D(new PVector(floorBottomRight3D.x - floorTopLeft3D.x, floorBottomRight3D.y - floorTopLeft3D.y, floorBottomRight3D.z - floorTopLeft3D.z), floorBottomRight2D);

    // Set it as calibrated.
    calibrated = true;
    //println("Calibrated");
  }

  calibrationLastStepTime = millis();
}

PVector normalizeVector(PVector vec) {
  float invLen = 1.0 / sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z);
  vec.x *= invLen;
  vec.y *= invLen;
  vec.z *= invLen;
  return vec;
}

float dotProduct(PVector a, PVector b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

PVector crossProduct(PVector a, PVector b, PVector out) {
  out.x = a.y * b.z - a.z * b.y;
  out.y = a.z * b.x - a.x * b.z;
  out.z = a.x * b.y - a.y * b.x;
  return out;
}

float wedgeProduct2D(PVector a, PVector b) {
  return a.x * b.y - a.y * b.x;
}

PVector project3DTo2D(PVector vec3D, PVector out) {
  out.x = dotProduct(vec3D, floorBasisX);
  out.y = dotProduct(vec3D, floorBasisY);
  return out;
}

PVector translate3DPointToUV(PVector vec3D, PVector out) {
  // Based on these:
  // http://reedbeta.com/blog/quadrilateral-interpolation-part-2/
  // https://www.particleincell.com/2012/quad-interpolation/
  // https://stackoverflow.com/questions/808441/inverse-bilinear-interpolation
  PVector vec3DRelative = new PVector(vec3D.x - floorTopLeft3D.x, vec3D.y - floorTopLeft3D.y, vec3D.z - floorTopLeft3D.z);
  PVector vec2D = project3DTo2D(vec3DRelative, new PVector());

  // For consistent naming with the formulae provided:
  PVector p = vec2D;
  PVector p0 = floorTopLeft2D;
  PVector p1 = floorTopRight2D;
  PVector p2 = floorBottomLeft2D;
  PVector p3 = floorBottomRight2D;

  PVector p0_p = new PVector(p0.x - p.x, p0.y - p.y);
  PVector p1_p = new PVector(p1.x - p.x, p1.y - p.y);
  PVector p0_2 = new PVector(p0.x - p2.x, p0.y - p2.y);
  PVector p1_3 = new PVector(p1.x - p3.x, p1.y - p3.y);
  float A = wedgeProduct2D(p0_p, p0_2);
  float B = (wedgeProduct2D(p0_p, p1_3) + wedgeProduct2D(p1_p, p0_2)) / 2;
  float C = wedgeProduct2D(p1_p, p1_3);
  float denom = A - 2 * B + C;
  float sqrtResult = sqrt(B * B - A * C);
  float possibleAnswer1 = ((A - B) + sqrtResult) / denom;
  float possibleAnswer2 = ((A - B) - sqrtResult) / denom;
  if (possibleAnswer1 >= 0 && possibleAnswer1 <= 1) {
    out.x = possibleAnswer1;
  } else
  {
    out.x = possibleAnswer2;
  }
  float denom1 = (1 - out.x) * (p0_2.x) + (out.x * p1_3.x);
  float denom2 = (1 - out.y) * (p0_2.y) + (out.y * p1_3.y);
  if (abs(denom1) > abs(denom2)) {
    out.y = ((1 - out.x) * (p0_p.x) + (out.x * p1_p.x)) / denom1;
  } else {
    out.y = ((1 - out.x) * (p0_p.y) + (out.x * p1_p.y)) / denom2;
  }

  return out;
}

void drawSkeleton(int userId) {
  stroke(0);
  strokeWeight(5);
  kinect.drawLimb(userId, SimpleOpenNI.SKEL_LEFT_KNEE, SimpleOpenNI.SKEL_LEFT_FOOT);
  kinect.drawLimb(userId, SimpleOpenNI.SKEL_RIGHT_KNEE, SimpleOpenNI.SKEL_RIGHT_FOOT);
  /*for(int j = 20; j <= 24; j = j + 4) {
   drawJoint(userId, j);
   }*/
  drawJoint(userId, SimpleOpenNI.SKEL_LEFT_FOOT);
  drawJoint(userId, SimpleOpenNI.SKEL_RIGHT_FOOT);
}

void drawJoint(int userId, int jointId) {
  PVector joint = new PVector();
  float confidence = kinect.getJointPositionSkeleton(userId, jointId, joint);
  if (confidence < confidenceThreshold) {
    return;
  }
  PVector convertedJoint = new PVector();
  kinect.convertRealWorldToProjective(joint, convertedJoint);
  float jointDisplayX = convertedJoint.x * (width / depthWidth);
  float jointDisplayY = convertedJoint.y * (height / depthHeight);
  //println("Position of " + jointId + " is " + jointDisplayX + ", " + jointDisplayY);
  noStroke();
  fill(255, 0, 0);
  ellipse(jointDisplayX, jointDisplayY, 25, 25);
  fill(255, 255, 255);
  //scale(3);
  textSize(48);
  text(jointId, jointDisplayX, jointDisplayY);
}

void drawFloor() {
  PVector convertedPosition = new PVector();
  float scaleX = (width / depthWidth);
  float scaleY = (height / depthHeight);
  noStroke();
  fill(0, 255, 0);
  //println("Converting front left " + floorFrontLeft.x + ", " + floorFrontLeft.y + ", " + floorFrontLeft.z);
  kinect.convertRealWorldToProjective(floorTopLeft3D, convertedPosition);
  //println("Converted to " + convertedPosition.x + ", " + convertedPosition.y + ", " + convertedPosition.z);
  ellipse(convertedPosition.x * scaleX, convertedPosition.y * scaleY, 25, 25);
  kinect.convertRealWorldToProjective(floorTopRight3D, convertedPosition);
  ellipse(convertedPosition.x * scaleX, convertedPosition.y * scaleY, 25, 25);
  kinect.convertRealWorldToProjective(floorBottomLeft3D, convertedPosition);
  ellipse(convertedPosition.x * scaleX, convertedPosition.y * scaleY, 25, 25);
  kinect.convertRealWorldToProjective(floorBottomRight3D, convertedPosition);
  ellipse(convertedPosition.x * scaleX, convertedPosition.y * scaleY, 25, 25);
}

void onNewUser(SimpleOpenNI kinect, int userId) {
  kinect.startTrackingSkeleton(userId);

  // If we've just found a new user and we haven't calibrated the playing field yet, trigger calibration.
  if (!calibrated) {
    calibrationLastStepTime = millis();
  }
}

public class SecondWindow extends PApplet {
  PApplet parentWindow;

  public SecondWindow(PApplet parentWindow, String title) {
    // See: https://stackoverflow.com/questions/39367111/close-additional-window-papplet
    super();
    this.parentWindow = parentWindow;
    PApplet.runSketch(new String[]{title}, this);
  }

  public void settings() {
    fullScreen(P2D, 2);
    //size(1280, 1024, P2D);
  }
  
  public void setup() {
    frameRate(25);
  }

  public void draw() {
    if (!calibrated) {
      // Display the calibration step we're at.
      background(50);
      fill(255);
      int arrowHeadSize = 25;
      strokeWeight(arrowHeadSize / 2);
      stroke(255);
      if (floorTopLeft3D.x == 0 && floorTopLeft3D.y == 0) {
        // Top left is the next one we're looking for.
        triangle(0, 0, arrowHeadSize, 0, 0, arrowHeadSize);
        line(0, 0, arrowHeadSize * 2, arrowHeadSize * 2);
      } else if (floorTopRight3D.x == 0 && floorTopRight3D.y == 0) {
        // Top right is the next one we're looking for.
        triangle(width - arrowHeadSize, 0, width, 0, width, arrowHeadSize);
        line(width, 0, width - arrowHeadSize * 2, arrowHeadSize * 2);
      } else if (floorBottomRight3D.x == 0 && floorBottomRight3D.y == 0) {
        // Bottom right is the next one we're looking for.
        triangle(width, height, width - arrowHeadSize, height, width, height - arrowHeadSize);
        line(width, height, width - arrowHeadSize * 2, height - arrowHeadSize * 2);
      } else if (floorBottomLeft3D.x == 0 && floorBottomLeft3D.y == 0) {
        // Bottom left is the next one we're looking for.
        triangle(0, height, 0, height - arrowHeadSize, arrowHeadSize, height);
        line(0, height, arrowHeadSize * 2, height - arrowHeadSize * 2);
      }
      
      // Display instructions.
      // Now that we know whether the player is in the circle, draw a "stand here to start" circle.
      pushMatrix();
      float textSize = height / 16;
      translate(width / 2, height / 2);
      textSize(textSize);
      fill(255, 255, 255);
      textAlign(CENTER, CENTER);
      String gameStartText = "Stand facing sensor with left foot on arrow to calibrate";
      text(gameStartText, -width / 4, -textSize * 2, width / 2, textSize * 3);
      popMatrix();
    } else {
      // Calibrated.  Time to play!
      drawGame(this, width, height);
    }
  }

  public void keyPressed() {
    parentWindow.keyPressed();
  }
}
