/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, GOOD TITLE or
 * NON INFRINGEMENT.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Copyright (C) 2005-2006  Guido de Jong <guidoj@users.sf.net>
 */

#include <iomanip>
#include <sstream>

#include "MediaToolkit.h"
#include "RatingsWidget.h"

RatingsWidget::RatingsWidget(const int x, const int y, const int w, const int h, PlayerCharacter *pc, FontResource &f)
: Widget(x, y, w, h)
, playerCharacter(pc)
, horizontalBorder(0)
, verticalBorder(0)
, ratingsLabel(0)
, conditionLabel(0)
, healthLabel(0)
, staminaLabel(0)
, speedLabel(0)
, strengthLabel(0)
, healthOfLabel(0)
, staminaOfLabel(0)
, actualHealth(0)
, actualStamina(0)
, actualSpeed(0)
, actualStrength(0)
, maximumHealth(0)
, maximumStamina(0)
, condition(0)
{
  ratingsLabel = new TextWidget(x + 11, y + 5, 40, 11, f);
  ratingsLabel->SetText("Ratings:");
  ratingsLabel->SetAlignment(HA_LEFT, VA_TOP);
  ratingsLabel->SetColor(RATINGS_TEXT_COLOR);
  ratingsLabel->SetShadow(COLOR_BLACK, 1, 1);
  conditionLabel = new TextWidget(x + 126, y + 5, 50, 11, f);
  conditionLabel->SetText("Condition:");
  conditionLabel->SetAlignment(HA_LEFT, VA_TOP);
  conditionLabel->SetColor(RATINGS_TEXT_COLOR);
  conditionLabel->SetShadow(COLOR_BLACK, 1, 1);
  healthLabel = new TextWidget(x + 21, y + 19, 40, 11, f);
  healthLabel->SetText("Health");
  healthLabel->SetAlignment(HA_LEFT, VA_TOP);
  healthLabel->SetColor(RATINGS_TEXT_COLOR);
  healthLabel->SetShadow(COLOR_BLACK, 1, 1);
  staminaLabel = new TextWidget(x + 21, y + 30, 40, 11, f);
  staminaLabel->SetText("Stamina");
  staminaLabel->SetAlignment(HA_LEFT, VA_TOP);
  staminaLabel->SetColor(RATINGS_TEXT_COLOR);
  staminaLabel->SetShadow(COLOR_BLACK, 1, 1);
  speedLabel = new TextWidget(x + 21, y + 41, 40, 11, f);
  speedLabel->SetText("Speed");
  speedLabel->SetAlignment(HA_LEFT, VA_TOP);
  speedLabel->SetColor(RATINGS_TEXT_COLOR);
  speedLabel->SetShadow(COLOR_BLACK, 1, 1);
  strengthLabel = new TextWidget(x + 21, y + 52, 40, 11, f);
  strengthLabel->SetText("Strength");
  strengthLabel->SetAlignment(HA_LEFT, VA_TOP);
  strengthLabel->SetColor(RATINGS_TEXT_COLOR);
  strengthLabel->SetShadow(COLOR_BLACK, 1, 1);
  healthOfLabel = new TextWidget(x + 86, y + 19, 12, 11, f);
  healthOfLabel->SetText("of");
  healthOfLabel->SetAlignment(HA_LEFT, VA_TOP);
  healthOfLabel->SetColor(RATINGS_TEXT_COLOR);
  healthOfLabel->SetShadow(COLOR_BLACK, 1, 1);
  staminaOfLabel = new TextWidget(x + 86, y + 30, 12, 11, f);
  staminaOfLabel->SetText("of");
  staminaOfLabel->SetAlignment(HA_LEFT, VA_TOP);
  staminaOfLabel->SetColor(RATINGS_TEXT_COLOR);
  staminaOfLabel->SetShadow(COLOR_BLACK, 1, 1);

  std::stringstream actualHealthStream;
  actualHealthStream << std::setw(2) << std::setfill(' ') << playerCharacter->GetStatistics().Get(STAT_HEALTH, STAT_ACTUAL);
  actualHealth = new TextWidget(x + 68, y + 19, 12, 11, f);
  actualHealth->SetText(actualHealthStream.str());
  actualHealth->SetAlignment(HA_RIGHT, VA_TOP);
  actualHealth->SetColor(RATINGS_TEXT_COLOR);
  actualHealth->SetShadow(COLOR_BLACK, 1, 1);
  std::stringstream actualStaminaStream;
  actualStaminaStream << std::setw(2) << std::setfill(' ') << playerCharacter->GetStatistics().Get(STAT_STAMINA, STAT_ACTUAL);
  actualStamina = new TextWidget(x + 68, y + 30, 12, 11, f);
  actualStamina->SetText(actualStaminaStream.str());
  actualStamina->SetAlignment(HA_RIGHT, VA_TOP);
  actualStamina->SetColor(RATINGS_TEXT_COLOR);
  actualStamina->SetShadow(COLOR_BLACK, 1, 1);
  std::stringstream actualSpeedStream;
  actualSpeedStream << std::setw(2) << std::setfill(' ') << playerCharacter->GetStatistics().Get(STAT_SPEED, STAT_ACTUAL);
  actualSpeed = new TextWidget(x + 68, y + 41, 12, 11, f);
  actualSpeed->SetText(actualSpeedStream.str());
  actualSpeed->SetAlignment(HA_RIGHT, VA_TOP);
  actualSpeed->SetColor(RATINGS_TEXT_COLOR);
  actualSpeed->SetShadow(COLOR_BLACK, 1, 1);
  std::stringstream actualStrengthStream;
  actualStrengthStream << std::setw(2) << std::setfill(' ') << playerCharacter->GetStatistics().Get(STAT_STRENGTH, STAT_ACTUAL);
  actualStrength = new TextWidget(x + 68, y + 52, 12, 11, f);
  actualStrength->SetText(actualStrengthStream.str());
  actualStrength->SetAlignment(HA_RIGHT, VA_TOP);
  actualStrength->SetColor(RATINGS_TEXT_COLOR);
  actualStrength->SetShadow(COLOR_BLACK, 1, 1);
  std::stringstream maximumHealthStream;
  maximumHealthStream << std::setw(2) << std::setfill(' ') << playerCharacter->GetStatistics().Get(STAT_HEALTH, STAT_MAXIMUM);
  maximumHealth = new TextWidget(x + 98, y + 19, 12, 11, f);
  maximumHealth->SetText(maximumHealthStream.str());
  maximumHealth->SetAlignment(HA_RIGHT, VA_TOP);
  maximumHealth->SetColor(RATINGS_TEXT_COLOR);
  maximumHealth->SetShadow(COLOR_BLACK, 1, 1);
  std::stringstream maximumStaminaStream;
  maximumStaminaStream << std::setw(2) << std::setfill(' ') << playerCharacter->GetStatistics().Get(STAT_STAMINA, STAT_MAXIMUM);
  maximumStamina = new TextWidget(x + 98, y + 30, 12, 11, f);
  maximumStamina->SetText(maximumStaminaStream.str());
  maximumStamina->SetAlignment(HA_RIGHT, VA_TOP);
  maximumStamina->SetColor(RATINGS_TEXT_COLOR);
  maximumStamina->SetShadow(COLOR_BLACK, 1, 1);
  condition = new TextWidget(x + 136, y + 19, 60, 11, f);
  switch (playerCharacter->GetCondition()) {
    case COND_NORMAL:
      condition->SetText("Normal");
      break;
    case COND_SICK:
      condition->SetText("Sick");
      break;
    case COND_PLAGUED:
      condition->SetText("Plagued");
      break;
    case COND_POISONED:
      condition->SetText("Poisoned");
      break;
    case COND_DRUNK:
      condition->SetText("Drunk");
      break;
    case COND_HEALING:
      condition->SetText("Healing");
      break;
    case COND_STARVING:
      condition->SetText("Starving");
      break;
    case COND_NEAR_DEATH:
      condition->SetText("Near-death");
      break;
    default:
      condition->SetText("");
      break;
  }
  condition->SetAlignment(HA_LEFT, VA_TOP);
  condition->SetColor(RATINGS_TEXT_COLOR);
  condition->SetShadow(COLOR_BLACK, 1, 1);
}

RatingsWidget::~RatingsWidget()
{
  if (ratingsLabel) {
    delete ratingsLabel;
  }
  if (conditionLabel) {
    delete conditionLabel;
  }
  if (healthLabel) {
    delete healthLabel;
  }
  if (staminaLabel) {
    delete staminaLabel;
  }
  if (speedLabel) {
    delete speedLabel;
  }
  if (strengthLabel) {
    delete strengthLabel;
  }
  if (healthOfLabel) {
    delete healthOfLabel;
  }
  if (staminaOfLabel) {
    delete staminaOfLabel;
  }
  if (actualHealth) {
    delete actualHealth;
  }
  if (actualStamina) {
    delete actualStamina;
  }
  if (actualSpeed) {
    delete actualSpeed;
  }
  if (actualStrength) {
    delete actualStrength;
  }
  if (maximumHealth) {
    delete maximumHealth;
  }
  if (maximumStamina) {
    delete maximumStamina;
  }
  if (condition) {
    delete condition;
  }
}

void
RatingsWidget::SetBorders(Image *hb, Image *vb)
{
  horizontalBorder = hb;
  verticalBorder = vb;
}

void
RatingsWidget::Draw()
{
  int xoff = 0;
  int yoff = 0;
  if (horizontalBorder && verticalBorder)
  {
    horizontalBorder->Draw(xpos + verticalBorder->GetWidth(), ypos,
                           xpos + verticalBorder->GetWidth(), ypos,
                           width - 2 * verticalBorder->GetWidth(), horizontalBorder->GetHeight());
    horizontalBorder->Draw(xpos + verticalBorder->GetWidth(), ypos + height - horizontalBorder->GetHeight(),
                           xpos + verticalBorder->GetWidth(), ypos + height - horizontalBorder->GetHeight(),
                           width - 2 * verticalBorder->GetWidth(), horizontalBorder->GetHeight());
    verticalBorder->Draw(xpos, ypos,
                         xpos, ypos,
                         verticalBorder->GetWidth(), height);
    verticalBorder->Draw(xpos + width - verticalBorder->GetWidth(), ypos,
                         xpos + width - verticalBorder->GetWidth(), ypos,
                         verticalBorder->GetWidth(), height);
    xoff = verticalBorder->GetWidth();
    yoff = horizontalBorder->GetHeight();
  }
  Video *video = MediaToolkit::GetInstance()->GetVideo();
  video->FillRect(xpos + xoff, ypos + yoff, width - 2 * xoff, height - 2 * yoff, 168);
  ratingsLabel->Draw();
  conditionLabel->Draw();
  healthLabel->Draw();
  staminaLabel->Draw();
  speedLabel->Draw();
  strengthLabel->Draw();
  healthOfLabel->Draw();
  staminaOfLabel->Draw();
  actualHealth->Draw();
  actualStamina->Draw();
  actualSpeed->Draw();
  actualStrength->Draw();
  maximumHealth->Draw();
  maximumStamina->Draw();
  condition->Draw();
}
