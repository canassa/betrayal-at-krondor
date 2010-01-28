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

TextBlock::TextBlock ( const TextBlock& tb )
        : words()
        , color ( tb.color )
        , shadow ( tb.shadow )
        , shadowXoff ( tb.shadowXoff )
        , shadowYoff ( tb.shadowYoff )
        , italic ( tb.italic )
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

Line::Line ( Font *f, int i )
        : font ( f )
        , textBlocks()
        , indent ( i )
        , width ( 0 )
{
}

Line::~Line()
{
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
    while ( s[i] != ' ' )
    {
        i++;
        wordWidth += font->GetWidth ( s[i] - font->GetFirst() );
    }
    word = s.substr ( 0, i );
}


void Line::AddWords ( TextBlock& tb, int w )
{
    int wordWidth = 0;
    std::string words ( tb.GetWords() );
    std::string word;
    CopyFirstWord ( words, word, wordWidth );
    for ( unsigned int i = 0; i < word.size(); i++ )
    {
        wordWidth += font->GetWidth ( word[i] - font->GetFirst() );
    }
    TextBlock tmp ( tb );
    while ( ( width + wordWidth ) <= w )
    {
        tmp.AddWords ( word );
        width += wordWidth;
    }
    textBlocks.push_back ( tmp );
}

int Line::GetWidth() const
{
    return width;
}

void Line::Draw ( int x, int y, int w, int h ) const
{
    int xoff = indent;
    for ( unsigned int i = 0; i < textBlocks.size(); i++ )
    {
        xoff = textBlocks[i].Draw ( x, y, w - xoff, h, font );
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
    Line line ( font, lineIndent );
    for ( unsigned int i = 0; i < textBlocks.size(); i++ )
    {
        TextBlock tb = textBlocks[i];
        line.AddWords ( tb, width - lineIndent );
        if ( tb.GetSize() > 0 )
        {
            lines.push_back ( line );
            lineIndent = 0;
        }
    }
    lines.push_back ( line );
}


void Paragraph::SetIndent ( int i )
{
    indent = i;
}

int Paragraph::Draw ( int x, int y, int w, int h, unsigned int& l ) const
{
    while ( ( h > font->GetHeight() ) && ( l < lines.size() ) )
    {
        lines[l].Draw ( x, y, w, font->GetHeight() );
        l++;
        y += font->GetHeight();
        h -= font->GetHeight();
    }
    return h;
}


Text::Text ( Font *f )
        : font ( f )
        , paragraphs()
        , currentParagraph ( 0 )
        , currentLine ( 0 )
{
}

Text::~Text()
{
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
        h = p.Draw ( x, y, w, h, currentLine );
        if ( currentLine >= p.GetLines().size() )
        {
            currentParagraph++;
            h += font->GetHeight() / 2;
        }
    }
}

void Text::DrawScroll ( int x, int y, int w, int h )
{
}
