/*
 * This file is part of xBaK.
 *
 * xBaK is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * xBaK is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with xBaK.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Copyright (C) Guido de Jong <guidoj@users.sf.net>
 */

#include "Exception.h"
#include "MediaToolkit.h"
#include "Text.h"
#include "Widget.h"

TextBlock::TextBlock ( const std::string& s, int c, int sh, int shx, int shy, bool it )
        : words ( s )
        , color ( c )
        , shadow ( sh )
        , shadowXoff ( shx )
        , shadowYoff ( shy )
        , italic ( it )
{
}

TextBlock::~TextBlock()
{
}


unsigned int TextBlock::GetSize() const
{
    return words.size();
}

void TextBlock::AddWords ( const std::string& s )
{
    words += s;
}


void TextBlock::EraseWords ( unsigned int n )
{
    words.erase ( 0, n );
}

const std::string& TextBlock::GetWords() const
{
    return words;
}

int TextBlock::Draw ( int x, int y, int w, int, Font* f ) const
{
    unsigned int i;
    int xoff;
    if ( ( shadow > NO_SHADOW ) && ( ( shadowXoff != 0 ) || ( shadowYoff != 0 ) ) )
    {
        i = 0;
        xoff = 0;
        while ( ( i < words.size() ) && ( xoff + f->GetWidth ( words[i] - f->GetFirst() ) < w ) )
        {
            f->DrawChar ( x + shadowXoff + xoff, y + shadowYoff, words[i], shadow, italic );
            xoff += f->GetWidth ( ( unsigned int ) words[i] - f->GetFirst() );
            i++;
        }
    }
    i = 0;
    xoff = 0;
    while ( ( i < words.size() ) && ( xoff + f->GetWidth ( words[i] - f->GetFirst() ) < w ) )
    {
        f->DrawChar ( x + xoff, y, words[i], color, italic );
        xoff += f->GetWidth ( ( unsigned int ) words[i] - f->GetFirst() );
        i++;
    }
    return xoff;
}

Line::Line ( Font *f )
        : font ( f )
        , textBlocks()
        , indent ( 0 )
        , width ( 0 )
{
}

Line::~Line()
{
    textBlocks.clear();
}

void Line::SetIndent ( int i )
{
    indent = i;
}

void Line::Clear()
{
    textBlocks.clear();
    width = 0;
}

void Line::CopyFirstWord ( std::string& s, std::string& word, int& wordWidth )
{
    wordWidth = 0;
    if ( s[0] == ' ' )
    {
        wordWidth += font->GetWidth ( s[0] - font->GetFirst() );
        s.erase ( 0, 1 );
    }
    unsigned int i = 0;
    while ( ( i < s.size() ) && ( s[i] > ' ' ) )
    {
        wordWidth += font->GetWidth ( s[i] - font->GetFirst() );
        i++;
    }
    word = s.substr ( 0, i );
}

void Line::AddWords ( TextBlock& tb, int w )
{
    std::string words = tb.GetWords();
    std::string word;
    int wordWidth = 0;
    TextBlock tmp ( "", tb.GetColor(), tb.GetShadow(), tb.GetShadowXOff(), tb.GetShadowYOff(), tb.GetItalic() );
    bool isFirstWord = true;
    while ( ( !words.empty() ) && ( ( width + wordWidth ) <= w ) )
    {
        CopyFirstWord ( words, word, wordWidth );
        wordWidth = isFirstWord ? 0 : font->GetWidth ( ' ' - font->GetFirst() );
        for ( unsigned int i = 0; i < word.size(); i++ )
        {
            wordWidth += font->GetWidth ( word[i] - font->GetFirst() );
        }
        if ( ( width + wordWidth ) <= w )
        {
            if ( !isFirstWord )
            {
                tmp.AddWords ( " " );
                tb.EraseWords ( 1 );
            }
            tmp.AddWords ( word );
            words.erase ( 0, word.size() );
            tb.EraseWords ( word.size() );
            width += wordWidth;
            isFirstWord = false;
        }
    }
    textBlocks.push_back ( tmp );
}

void Line::Draw ( int x, int y, int w, int h ) const
{
    int xoff = indent;
    for ( unsigned int i = 0; i < textBlocks.size(); i++ )
    {
        xoff = textBlocks[i].Draw ( x + xoff, y, w - xoff, h, font );
    }
}


Paragraph::Paragraph ( Font *f )
        : font ( f )
        , textBlocks()
        , lines()
        , horAlign ( HA_LEFT )
        , vertAlign ( VA_TOP )
        , indent ( 0 )
{
}

Paragraph::~Paragraph()
{
    textBlocks.clear();
    lines.clear();
}

unsigned int Paragraph::GetSize() const
{
    return textBlocks.size();
}

const std::vector< Line >& Paragraph::GetLines() const
{
    return lines;
}

void Paragraph::AddTextBlock ( const TextBlock& tb )
{
    textBlocks.push_back ( tb );
}

void Paragraph::SetAlignment ( const HorizontalAlignment ha, const VerticalAlignment va )
{
    horAlign = ha;
    vertAlign = va;
}

void Paragraph::GenerateLines ( int width, int extraIndent )
{
    lines.clear();
    int lineIndent = indent + extraIndent;
    Line line ( font );
    line.SetIndent( lineIndent );
    for ( unsigned int i = 0; i < textBlocks.size(); i++ )
    {
        TextBlock tb = textBlocks[i];
        while ( tb.GetSize() > 0 )
        {
            line.AddWords ( tb, width - lineIndent );
            if ( ( line.GetWidth() > 0 ) && ( tb.GetSize() > 0 ) )
            {
                lines.push_back ( line );
                line.Clear();
                lineIndent = 0;
                line.SetIndent( lineIndent );
                if ( tb.GetWords()[0] == ' ' )
                {
                    tb.EraseWords ( 1 );
                }
            }
        }
    }
    if ( line.GetWidth() > 0 )
    {
        lines.push_back ( line );
    }
}

void Paragraph::SetIndent ( int i )
{
    indent = i;
}

void Paragraph::Draw ( int x, int &y, int w, int &h, unsigned int& l ) const
{
    while ( ( h > font->GetHeight() ) && ( l < lines.size() ) )
    {
        lines[l].Draw ( x, y, w, font->GetHeight() );
        l++;
        y += font->GetHeight();
        h -= font->GetHeight();
    }
}


Text::Text()
        : paragraphs()
        , currentParagraph ( 0 )
        , currentLine ( 0 )
{
}

Text::~Text()
{
    paragraphs.clear();
}

unsigned int Text::GetSize() const
{
    return paragraphs.size();
}


void Text::AddParagraph ( const Paragraph& p )
{
    paragraphs.push_back ( p );
}

void Text::GenerateLines ( int width, int initialIndent )
{
    for ( unsigned int i = 0; i < paragraphs.size(); i++ )
    {
        paragraphs[i].GenerateLines ( width, initialIndent );
        initialIndent = 0;
    }
    currentParagraph = 0;
    currentLine = 0;
}

void Text::DrawPage ( int x, int y, int w, int h )
{
    while ( ( h > 0 ) && ( currentParagraph < paragraphs.size() ) )
    {
        Paragraph p = paragraphs[currentParagraph];
        p.Draw ( x, y, w, h, currentLine );
        if ( currentLine >= p.GetLines().size() )
        {
            currentParagraph++;
            currentLine = 0;
            h -= 4;
            y += 4;
        }
    }
}

void Text::DrawScroll ( int x, int y, int w, int h )
{
}
