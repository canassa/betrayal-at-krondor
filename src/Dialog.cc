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
 * Copyright (C) 2005-2007  Guido de Jong <guidoj@users.sf.net>
 */

#include "Exception.h"
#include "Dialog.h"
#include "PointerManager.h"
#include "RequestResource.h"

Dialog::Dialog(Palette *pal, DialogWindow *dialogWin)
        : window(dialogWin)
        , palette(pal)
        , action(0)
        , running(false)
{
    try
    {
        PointerManager::GetInstance()->SetCurrentPointer(NORMAL_POINTER);
        PointerManager::GetInstance()->GetCurrentPointer()->SetVisible(true);
    }
    catch (Exception &e)
    {
        e.Print("Dialog::Dialog");
        throw;
    }
}

Dialog::~Dialog()
{
    // palette gets deleted elsewhere
    if (window)
    {
        delete window;
    }
}

void
Dialog::Enter()
{
    try
    {
        MediaToolkit* media = MediaToolkit::GetInstance();
        media->GetVideo()->Clear();
        PointerManager::GetInstance()->GetCurrentPointer()->Attach(this);
        window->FadeIn(palette);
        media->AddKeyboardListener(this);
        media->AddPointerButtonListener(this);
        media->AddDragListener(this);
        media->AddDropListener(this);
    }
    catch (Exception &e)
    {
        e.Print("Dialog::Enter");
        throw;
    }
}

void
Dialog::Leave()
{
    try
    {
        MediaToolkit* media = MediaToolkit::GetInstance();
        window->FadeOut(palette);
        window->PointerOverWidget(VIDEO_WIDTH, VIDEO_HEIGHT);
        media->RemoveDropListener(this);
        media->RemoveDragListener(this);
        media->RemovePointerButtonListener(this);
        media->RemoveKeyboardListener(this);
        PointerManager::GetInstance()->GetCurrentPointer()->Detach(this);
        media->GetVideo()->Clear();
    }
    catch (Exception &e)
    {
        e.Print("Dialog::Leave");
        throw;
    }
}

int
Dialog::Execute()
{
    try
    {
        running = true;
        while (running)
        {
            MediaToolkit::GetInstance()->PollEvents();
        }
        return action;
    }
    catch (Exception &e)
    {
        e.Print("Dialog::Execute");
        throw;
    }
}

void
Dialog::Update()
{
    window->Draw();
}

void
Dialog::PointerButtonPressed(const PointerButtonEvent& pbe)
{
    if (running)
    {
        switch (pbe.GetButton())
        {
            case PB_PRIMARY:
                window->LeftClickWidget(true, pbe.GetXPos(), pbe.GetYPos());
                break;
            case PB_SECONDARY:
                window->RightClickWidget(true, pbe.GetXPos(), pbe.GetYPos());
                break;
            default:
                break;
        }
    }
    window->Draw();
}

void
Dialog::PointerButtonReleased(const PointerButtonEvent& pbe)
{
    switch (pbe.GetButton())
    {
        case PB_PRIMARY:
            window->LeftClickWidget(false, pbe.GetXPos(), pbe.GetYPos());
            break;
        case PB_SECONDARY:
            window->RightClickWidget(false, pbe.GetXPos(), pbe.GetYPos());
            break;
        default:
            break;
    }
    window->Draw();
}

void
Dialog::ActionPerformed(const ActionEvent& ae)
{
    action = ae.GetAction();
    running = false;
}

void
Dialog::WidgetDragged(const DragEvent& die)
{
    if (running)
    {
        die.GetXPos();
    }
    window->Draw();
}

void
Dialog::WidgetDropped(const DropEvent& die)
{
    if (running)
    {
        die.GetXPos();
    }
    window->Draw();
}


GameDialog::GameDialog(Palette *pal, DialogWindow *dialogwin)
        : Dialog(pal, dialogwin)
{}

GameDialog::~GameDialog()
{}

void
GameDialog::KeyPressed(const KeyboardEvent& kbe)
{
    if (running)
    {
        switch (kbe.GetKey())
        {
        case KEY_ESCAPE:
            action = ACT_ESCAPE;
            running = false;
            break;
        case KEY_TAB:
            window->SelectNextWidget();
            break;
        case KEY_UP:
            action = ACT_UP;
            running = false;
            break;
        case KEY_DOWN:
            action = ACT_DOWN;
            running = false;
            break;
        case KEY_LEFT:
            action = ACT_LEFT;
            running = false;
            break;
        case KEY_RIGHT:
            action = ACT_RIGHT;
            running = false;
            break;
        default:
            break;
        }
    }
    window->Draw();
}

void
GameDialog::KeyReleased(const KeyboardEvent& kbe)
{
    switch (kbe.GetKey())
    {
    default:
        break;
    }
}


OptionsDialog::OptionsDialog(Palette *pal, DialogWindow *dialogwin)
        : Dialog(pal, dialogwin)
{}

OptionsDialog::~OptionsDialog()
{}

void
OptionsDialog::KeyPressed(const KeyboardEvent& kbe)
{
    if (running)
    {
        switch (kbe.GetKey())
        {
        case KEY_ESCAPE:
            action = ACT_ESCAPE;
            running = false;
            break;
        case KEY_DOWN:
        case KEY_TAB:
            window->SelectNextWidget();
            break;
        case KEY_UP:
            window->SelectPreviousWidget();
            break;
        case KEY_RETURN:
        case KEY_SPACE:
            window->LeftClickWidget(true);
            break;
        default:
            break;
        }
    }
    window->Draw();
}

void
OptionsDialog::KeyReleased(const KeyboardEvent& kbe)
{
    switch (kbe.GetKey())
    {
    case KEY_RETURN:
    case KEY_SPACE:
        window->LeftClickWidget(false);
        break;
    default:
        break;
    }
    window->Draw();
}
