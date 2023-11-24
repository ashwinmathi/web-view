Web View
============

Type-safe HTML and CSS with simplified layout and easy composition of styles. Inspired by Tailwindcss and Elm-UI

[![Hackage](https://img.shields.io/hackage/v/web-view.svg)][hackage]

Write Haskell instead of CSS
----------------------------

Type-safe utility functions to style html

```haskell
myPage = col (gap 10) $ do
  el (bold . fontSize 32) "My page"
  button (color Red) "Click Me"
```

Re-use styles as Haskell functions instead of naming CSS classes.

```haskell
header = bold
h1 = header . fontSize 32
h2 = header . fontSize 24
page = gap 10

myPage = col page $ do
  el h1 "My Page"
  ...
```

This approach is inspired by Tailwindcss' [Utility Classes](https://tailwindcss.com/docs/utility-first)

Simplified Layouts
------------------

Easily create layouts with `row`, `col`, and `grow`

https://github.com/seanhess/web-view/blob/52fafd9620f2df88197733a436c1af12b3533d88/example/Example/Layout.hs#L36-L48


Embedded CSS
------------

Views track which styles are used in any child node, and automatically embed all CSS when rendered. 

    >>> renderText () $ el bold "Hello"
    <style type='text/css'>.bold { font-weight:bold }</style>
    <div class='bold'>Hello</div>


Stateful Styles
---------------

We can apply styles when certain states apply. For example, to change the background on hover:

```haskell
    button (bg Primary . hover (bg PrimaryLight)) "Hover Me"
```

Media states allow us to create responsive designs

```haskell
    el (width 100 . media (MinWidth 800) (width 400))
      "Big if window > 800"
```


Learn More
----------

View Documentation on [Hackage][hackage]
* https://hackage.haskell.org/package/aeson-2.2.1.0

View on Github
* https://github.com/seanhess/web-view



[hackage]: https://hackage.haskell.org/package/aeson-2.2.1.0
