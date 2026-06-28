" Auto-install vim-plug if not present
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
endif

" Auto-install plugins on first startup
if empty(glob('~/.vim/plugged'))
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Use Vim settings, rather then Vi settings (much better!).
" This must be first, because it changes other options as a side effect.
set nocompatible

"  vim-plug setup
call plug#begin('~/.vim/plugged')

" File explorer
Plug 'scrooloose/nerdtree'

" Linting (ALE replaces Syntastic)
Plug 'dense-analysis/ale'

" Color scheme
Plug 'altercation/vim-colors-solarized'

" Status bar
Plug 'bling/vim-airline'

" Git integration
Plug 'airblade/vim-gitgutter'

" Indent guides
Plug 'nathanaelkane/vim-indent-guides'

" Whitespace management
Plug 'ntpeters/vim-better-whitespace'

" TypeScript support
Plug 'leafgarland/typescript-vim'

" JavaScript support
Plug 'pangloss/vim-javascript'

call plug#end()

filetype plugin indent on

" Enable solarized for vim coloring
syntax enable
set background=dark
colorscheme solarized

" Essential settings
set hidden                  " Allow switching buffers without saving
set incsearch              " Incremental search
set hlsearch               " Highlight search results
set ignorecase             " Case-insensitive search
set smartcase              " Case-sensitive when uppercase
set showmatch              " Show matching brackets
set wildmenu               " Better command-line completion
set wildmode=list:longest  " Complete to longest common string
set history=1000           " Remember more commands
set undolevels=1000        " Remember more undo levels

" Search and replace improvements
set gdefault               " Always use global flag for search/replace
set magic                  " Use magic for regex

" allow backspacing over everything in insert mode
set backspace=indent,eol,start


" Tell vim to remember certain things when we exit
"  '10  :  marks will be remembered for up to 10 previously edited files
"  "100 :  will save up to 100 lines for each register
"  :20  :  up to 20 lines of command-line history will be remembered
"  %    :  saves and restores the buffer list
"  n... :  where to save the viminfo files
set viminfo='10,\"100,:20,%,n~/.viminfo

"A whole bunch of bs below to remember our cursor postion
function! ResCur()
  if line("'\"") <= line("$")
    normal! g`"
    return 1
  endif
endfunction

augroup resCur
  autocmd!
  autocmd BufWinEnter * call ResCur()
augroup END

" enable auto-indentation as well as set the tab to 4 spaces
set smartindent
set tabstop=4
set shiftwidth=4

" converts all tabs to spaces...
set expandtab

" colorscheme ir_black
set bg=dark


set nobackup
set nowritebackup

"enable number lines to always be on by default
set nu

"Draw a nice little grey bar when its time to wrap your code
highlight ColorColumn ctermbg=lightgrey guibg=lightgrey
set colorcolumn=100

"---------------------------------------------
"Nerdtree related shit below
"----------------------------------------------

"setup the nerdtree toggle button (make sure it's installed)
map <C-n> :NERDTreeToggle<CR>

"Automatically open Nerdtree when you start vim (disabled)
"autocmd vimenter * NERDTree
"start on the editing window if you specified a file to open with vim (disabled)
"autocmd vimEnter * if argc() == 1 | NERDTree | wincmd p | endif

"if you started with vim and you close all windows autoclose the nerdtree
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

"---------------------------------------------
"ALE (replaces Syntastic) - Async Linting Engine
"----------------------------------------------
"ALE configuration is handled above in the main settings section

"setup our indent guildines with vim-indent-guides
let g:indent_guides_start_level = 2
let g:indent_guides_guide_size = 1
map <C-i> :IndentGuidesToggle<CR>
let g:indent_guides_auto_colors = 0
autocmd VimEnter,Colorscheme * :hi IndentGuidesOdd ctermbg=lightgrey
autocmd VimEnter,Colorscheme * :hi IndentGuidesEven ctermbg=darkgrey

"Create a quick toggle to fix whitespace
"https://github.com/ntpeters/vim-better-whitespace
highlight ExtraWhitespace ctermbg=blue
autocmd BufEnter * EnableStripWhitespaceOnSave