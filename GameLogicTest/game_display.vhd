library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity game_display is
    port (
        clk: in std_logic;
        hsync, vsync : out std_logic;
        red, green, blue : out std_logic_vector(3 downto 0);
        BTNU, BTND, BTNL, BTNR: in std_logic
    );
end game_display;  

architecture game_display_arch of game_display is
signal clk50MHz : std_logic;
signal clk100Hz: std_logic; -- Fast debounce clock (10ms period, 100Hz)
signal hcount, vcount : integer := 0;

-- Maze cell/block constants
constant CELL_SIZE : integer := 32;
constant MAZE_WIDTH : integer := 30; -- 960 / 32 = 30 cells
constant MAZE_HEIGHT : integer := 18; -- 576 / 32 = 18 cells

-- VGA timing constants
constant H_TOTAL : integer := 1344 -1;
constant H_SYNC : integer := 48 -1;
constant H_BACK : integer := 240 -1;
constant H_START : integer := 48 + 240 -1;
constant H_ACTIVE : integer := 1024 -1;
constant H_END : integer := 48 + 240 + 1024 -1;
constant H_FRONT : integer := 32 -1;
constant V_TOTAL : integer := 625 -1;
constant V_SYNC : integer := 3 -1;
constant V_BACK : integer := 12 -1;
constant V_START : integer := 3 + 12 -1;
constant V_ACTIVE : integer := 600 -1;
constant V_END : integer := 3 + 12 + 600 -1;
constant V_FRONT : integer := 10 -1;

-- Player/monster size (equal to cell size)
constant PLAYER_SIZE : integer := CELL_SIZE;

-- Maze representation (1=wall, 0=path)
type MAZE_ARRAY is array (0 to MAZE_HEIGHT-1, 0 to MAZE_WIDTH-1) of std_logic;
constant MAZE1 : MAZE_ARRAY := (
    -- 30x18 maze, start at [1,1], end at [1,2]
    "111111111111111111111111111111",
    "100000000000011111110000000001",
    "101111111110110000001011111101",
    "101000000010000111101000000101",
    "101011110011111000001111101101",
    "101010000000001111110000001101",
    "101011111111101000000111111101",
    "101000000100001011110000000101",
    "101111110111111010001111111101",
    "100000000100000010100000000101",
    "101111111101111111011111111101",
    "100000000001000000000000000101",
    "101111111111011111111111111101",
    "101000000000000100000000000101",
    "101011111111110111111111111101",
    "101000000000000000000000000101",
    "101111111111111111111111111101",
    "111111111111111111111111111111"
);
constant MAZE2 : MAZE_ARRAY := (
    -- 30x18 maze, start at [1,28], end at [16,1]
    "111111111111111111111111111111",
    "100000000000000000000000000001",
    "101111111111111111111111111101",
    "101000000000000000000000000101",
    "101011111111111111111111110101",
    "101010000000000000000000010101",
    "101011111111111111111110110101",
    "101000000000000000000010000101",
    "101111111111111111110111111101",
    "100000000000000000010000000101",
    "101111111111111110111111111101",
    "100000000000000010000000000101",
    "101111111111111011111111111101",
    "101000000000010000000000000101",
    "101011111111011111111111110101",
    "101000000000000000000000000101",
    "101111111111111111111111111101",
    "111111111111111111111111111111"
);
constant MAZE3 : MAZE_ARRAY := (
    -- 30x18 maze, start at [16,28], end at [1,1]
    "111111111111111111111111111111",
    "100000000000000000000000000001",
    "101111111111111111111111111101",
    "101000000000000000000000000101",
    "101011111111111111111111110101",
    "101010000000000000000000010101",
    "101011111111111111111110110101",
    "101000000000000000000010000101",
    "101111111111111111110111111101",
    "100000000000000000010000000101",
    "101111111111111110111111111101",
    "100000000000000010000000000101",
    "101111111111111011111111111101",
    "101000000000010000000000000101",
    "101011111111011111111111110101",
    "101000000000000000000000000101",
    "101111111111111111111111111101",
    "111111111111111111111111111111"
);

-- Level tracking
signal level : integer range 1 to 3 := 1;

-- Add integer_vector type for level arrays
type integer_vector is array (natural range <>) of integer;

-- Start and end cell coordinates for each level (ensure these are on path cells)
constant START_ROW_ARR : integer_vector(1 to 3) := (1, 16, 16);
constant START_COL_ARR : integer_vector(1 to 3) := (1, 28, 1);
constant END_ROW_ARR   : integer_vector(1 to 3) := (16, 16, 1);
constant END_COL_ARR   : integer_vector(1 to 3) := (28, 1, 28);

-- Player position in cell grid (row, col)
signal player_row : integer := START_ROW_ARR(1);
signal player_col : integer := START_COL_ARR(1);

-- Game over flag
signal game_over : std_logic := '0';

-- Previous button states for edge detection
signal prev_BTNU, prev_BTND, prev_BTNL, prev_BTNR: std_logic := '0';

-- GAME OVER message map (30 cols x 18 rows, each cell is a block)
-- '1' = yellow block, '0' = black. Message is centered in the 30x18 grid.
type MESSAGE_ARRAY is array (0 to MAZE_HEIGHT-1, 0 to MAZE_WIDTH-1) of std_logic;
constant GAME_OVER_MSG : MESSAGE_ARRAY := (
    -- Each string represents a row; 30 chars per line
    -- (SPACES)
    "000000000000000000000000000000",
    "000000000000000000000000000000",
    "000000000000000000000000000000",
    -- G A M E
    "000000111001100100010111100000",
    "000001000010010110110100000000",
    "000001011011110101010111000000",
    "000001001010010100010100000000",
    "000000111010010100010111100000",
    "000000000000000000000000000000",
    "000000000000000000000000000000",
    -- O V E R
    "000000110010001011110111000000",
    "000001001010001010000100100000",
    "000001001001010011100111000000",
    "000001001001010010000100100000",
    "000000110000100011110100100000",
    -- (SPACES)
    "000000000000000000000000000000",
    "000000000000000000000000000000",
    "000000000000000000000000000000"
);

-- Message area covers the entire maze
constant MSG_ROWS : integer := MAZE_HEIGHT;
constant MSG_COLS : integer := MAZE_WIDTH;
constant MSG_SCREEN_TOP  : integer := 0;
constant MSG_SCREEN_LEFT : integer := 0;

-- Colour declaration
type colours is(
    -- WALLS
    gap, b5, b4, b3, b2, b1,
    -- PATHS
    dark, mid, light, pebble, ground,
    -- PLAYER
    -- bacKground, Black, White, Grey, Red, Light green, Medium green, Dark green, Skin
    k, b, w, g, r, l, m, d, s,
    -- MONSTER
    -- Purple, Charcoal, (Black), (White), winE, (Grey), (Red)
    p, c, e
);

-- 2D array for assigning specific colours (32x32 pixels)
type pixel is array (0 to 31, 0 to 31) of colours;

-- WALLS
constant WALLS : pixel := (
    -- Rows 0-7: bricks, staggered
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap),
    -- Rows 8-15: staggered by 4 px
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap),
    -- Rows 16-23: same as 0-7
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (b5,b5,b5,b5,b5,b5,b5,gap, b4,b4,b4,b4,b4,b4,b4,gap, b3,b3,b3,b3,b3,b3,b3,gap, b2,b2,b2,b2,b2,b2,b2,gap),
    (gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap),
    -- Rows 24-31: staggered by 4 px
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,b1,b1,b1,b1,b1,b1,b1, gap,b5,b5,b5,b5,b5,b5,b5, gap,b4,b4,b4,b4,b4,b4,b4, gap,b3,b3,b3,b3,b3,b3,b3),
    (gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap, gap,gap,gap,gap,gap,gap,gap,gap)
);

constant PATHS : pixel := (
    -- Row 0
    (ground, mid, dark, ground, light, ground, mid, pebble, ground, dark, ground, pebble, mid, light, ground, dark, ground, mid, pebble, ground, light, ground, dark, pebble, mid, ground, pebble, light, ground, mid, ground, dark),
    -- Row 1
    (mid, ground, pebble, light, mid, dark, pebble, ground, light, pebble, ground, mid, light, ground, pebble, dark, ground, light, mid, pebble, ground, pebble, dark, light, mid, ground, light, mid, pebble, ground, light, dark),
    -- Row 2
    (dark, pebble, ground, mid, pebble, light, ground, dark, light, pebble, mid, ground, pebble, light, ground, mid, pebble, dark, ground, light, pebble, mid, light, dark, ground, pebble, light, mid, ground, dark, pebble, light),
    -- Row 3
    (ground, pebble, mid, dark, ground, light, mid, pebble, dark, ground, pebble, light, ground, dark, pebble, mid, light, ground, pebble, mid, dark, ground, light, pebble, mid, ground, dark, pebble, light, mid, ground, dark),
    -- Row 4
    (pebble, ground, light, mid, pebble, dark, ground, light, pebble, mid, ground, pebble, light, dark, mid, ground, pebble, light, ground, dark, pebble, mid, ground, light, pebble, dark, ground, light, mid, pebble, ground, dark),
    -- Row 5
    (light, mid, ground, pebble, dark, light, mid, ground, pebble, light, dark, ground, light, pebble, mid, dark, ground, pebble, light, mid, ground, dark, pebble, light, ground, pebble, dark, mid, light, ground, pebble, mid),
    -- Row 6
    (ground, pebble, light, dark, mid, ground, pebble, light, dark, ground, light, mid, pebble, ground, pebble, dark, light, mid, ground, pebble, light, dark, ground, pebble, mid, light, ground, pebble, dark, light, pebble, mid),
    -- Row 7
    (pebble, ground, dark, pebble, mid, ground, light, pebble, dark, light, ground, pebble, light, mid, ground, dark, pebble, light, mid, ground, pebble, dark, ground, light, mid, pebble, light, dark, ground, pebble, mid, light),
    -- Row 8
    (light, pebble, ground, dark, mid, pebble, light, ground, dark, pebble, light, mid, ground, pebble, dark, light, ground, pebble, mid, ground, dark, pebble, light, mid, ground, pebble, dark, light, pebble, mid, ground, pebble),
    -- Row 9
    (dark, mid, pebble, ground, light, dark, pebble, mid, ground, light, pebble, dark, ground, light, mid, pebble, light, dark, ground, pebble, mid, ground, dark, pebble, light, mid, ground, dark, pebble, light, ground, pebble),
    -- Row 10
    (ground, light, pebble, dark, mid, ground, pebble, light, dark, mid, pebble, ground, light, pebble, dark, ground, mid, light, pebble, dark, ground, light, pebble, mid, light, ground, dark, pebble, light, pebble, mid, ground),
    -- Row 11
    (pebble, ground, mid, light, dark, pebble, ground, light, mid, dark, pebble, light, ground, pebble, mid, dark, ground, light, pebble, mid, light, dark, ground, pebble, light, mid, dark, pebble, ground, light, pebble, mid),
    -- Row 12
    (ground, dark, pebble, light, mid, ground, pebble, dark, light, mid, pebble, light, ground, dark, pebble, light, mid, ground, pebble, dark, light, pebble, mid, ground, light, pebble, dark, mid, ground, dark, pebble, light),
    -- Row 13
    (mid, ground, pebble, light, dark, ground, pebble, light, mid, pebble, dark, ground, pebble, light, mid, dark, ground, pebble, light, dark, mid, ground, pebble, light, pebble, dark, ground, mid, light, pebble, ground, dark),
    -- Row 14
    (pebble, light, mid, ground, dark, pebble, light, ground, mid, dark, pebble, ground, light, pebble, mid, dark, ground, light, pebble, pebble, mid, dark, ground, light, pebble, dark, mid, ground, pebble, light, mid, ground),
    -- Row 15
    (ground, pebble, dark, light, mid, pebble, ground, dark, light, mid, pebble, ground, pebble, light, dark, mid, pebble, ground, light, dark, pebble, mid, ground, light, pebble, dark, mid, ground, pebble, light, mid, dark),
    -- Row 16
    (light, pebble, ground, mid, dark, pebble, light, ground, pebble, mid, dark, light, ground, pebble, mid, dark, light, pebble, ground, mid, pebble, light, dark, pebble, ground, light, mid, dark, pebble, mid, ground, pebble),
    -- Row 17
    (ground, light, pebble, dark, ground, pebble, light, mid, dark, ground, pebble, light, mid, dark, ground, pebble, light, pebble, mid, ground, dark, pebble, light, dark, ground, pebble, light, mid, pebble, dark, ground, mid),
    -- Row 18
    (pebble, ground, dark, light, pebble, mid, ground, dark, pebble, light, mid, ground, pebble, light, dark, mid, ground, pebble, light, pebble, dark, ground, mid, light, pebble, dark, ground, pebble, light, mid, dark, ground),
    -- Row 19
    (light, pebble, mid, dark, pebble, ground, light, pebble, mid, dark, ground, pebble, light, mid, dark, pebble, ground, light, dark, pebble, mid, ground, pebble, light, mid, dark, ground, pebble, light, dark, pebble, ground),
    -- Row 20
    (ground, dark, pebble, light, mid, pebble, ground, dark, light, pebble, mid, ground, pebble, light, dark, mid, ground, pebble, light, dark, pebble, ground, mid, light, pebble, dark, ground, pebble, light, mid, dark, ground),
    -- Row 21
    (pebble, light, ground, mid, dark, pebble, ground, mid, pebble, light, dark, ground, pebble, mid, light, pebble, dark, ground, light, mid, pebble, ground, dark, pebble, light, mid, ground, dark, pebble, light, mid, ground),
    -- Row 22
    (dark, pebble, light, ground, pebble, mid, dark, light, pebble, ground, mid, dark, pebble, light, ground, pebble, mid, light, ground, dark, pebble, light, mid, pebble, ground, dark, light, pebble, mid, ground, pebble, light),
    -- Row 23
    (ground, pebble, dark, mid, light, pebble, ground, dark, pebble, light, mid, ground, pebble, light, dark, mid, ground, pebble, light, mid, dark, pebble, light, ground, mid, pebble, dark, light, pebble, ground, mid, pebble),
    -- Row 24
    (light, mid, pebble, dark, ground, light, pebble, mid, dark, ground, pebble, light, dark, mid, ground, pebble, light, mid, pebble, dark, ground, pebble, light, dark, ground, pebble, mid, light, pebble, dark, mid, ground),
    -- Row 25
    (pebble, ground, dark, pebble, light, mid, ground, dark, light, pebble, mid, ground, pebble, light, dark, pebble, ground, light, mid, dark, pebble, ground, light, mid, pebble, dark, light, ground, pebble, mid, light, pebble),
    -- Row 26
    (dark, pebble, ground, light, mid, pebble, light, dark, ground, pebble, light, mid, dark, pebble, ground, light, pebble, dark, ground, light, pebble, mid, ground, dark, pebble, light, mid, ground, pebble, dark, light, pebble),
    -- Row 27
    (light, ground, mid, pebble, dark, pebble, light, mid, ground, dark, pebble, light, mid, ground, pebble, dark, light, pebble, ground, mid, light, dark, pebble, ground, light, mid, pebble, dark, light, pebble, ground, mid),
    -- Row 28
    (pebble, dark, ground, light, pebble, mid, dark, light, ground, pebble, light, mid, dark, ground, pebble, light, mid, pebble, dark, ground, light, pebble, mid, dark, ground, pebble, light, mid, dark, pebble, ground, light),
    -- Row 29
    (ground, pebble, light, mid, dark, pebble, ground, pebble, light, dark, mid, ground, pebble, light, dark, mid, ground, pebble, light, dark, pebble, ground, mid, light, pebble, dark, ground, pebble, light, mid, dark, pebble),
    -- Row 30
    (light, mid, ground, pebble, dark, light, pebble, mid, dark, ground, pebble, light, dark, mid, pebble, ground, light, mid, pebble, dark, ground, pebble, light, dark, mid, ground, pebble, light, dark, pebble, light, mid),
    -- Row 31
    (pebble, light, dark, ground, mid, pebble, light, dark, ground, light, pebble, mid, ground, dark, pebble, light, mid, pebble, dark, ground, light, pebble, mid, dark, ground, pebble, light, mid, dark, ground, light, pebble)
);

constant PLAYER : pixel := (
    -- Row 0 
    (k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, b, b, b, k, k, k, k, k, k, k, k), 
    -- Row 1
    (k, k, k, k, k, k, k, b, b, b, k, k, k, k, k, k, k, k, k, k, b, b, r, b, b, k, k, k, k, k, k, k), 
    -- Row 2
    (k, k, k, k, k, k, b, b, r, b, b, b, b, b, b, b, b, b, b, b, b, b, b, r, b, k, k, k, k, k, k, k), 
    -- Row 3
    (k, k, k, k, k, b, m, b, b, r, b, m, m, m, m, m, m, m, m, m, m, b, b, r, b, b, k, k, k, k, k, k), 
    -- Row 4
    (k, k, k, k, b, m, m, m, b, b, r, b, m, m, m, m, m, m, b, m, m, m, m, b, b, m, b, k, k, k, k, k), 
    -- Row 5
    (k, k, k, k, b, m, m, m, b, r, b, m, m, m, m, m, m, m, m, b, m, m, m, m, b, m, b, k, k, k, k, k), 
    -- Row 6
    (k, k, k, b, m, m, m, b, r, b, m, m, m, m, m, m, m, m, m, m, m, m, m, m, m, b, b, k, k, k, k, k), 
    -- Row 7
    (k, k, k, b, m, m, m, r, b, m, m, m, m, m, m, m, m, m, m, m, m, m, m, m, m, m, b, k, k, k, k, k), 
    -- Row 8
    (k, k, b, m, m, m, b, b, m, m, m, b, m, m, m, m, m, m, m, b, m, m, m, m, w, m, b, k, k, k, k, k), 
    -- Row 9
    (k, k, b, m, m, m, b, m, m, m, b, m, m, m, m, m, m, m, m, b, m, w, w, w, m, m, m, b, k, k, k, k), 
    -- Row 10
    (k, k, b, m, m, m, b, m, m, m, b, m, w, w, w, m, w, w, b, s, b, m, m, m, m, m, m, b, k, k, k, k), 
    -- Row 11
    (k, b, m, m, m, m, b, m, m, m, b, m, m, m, m, b, m, m, b, s, b, b, m, m, b, m, m, b, k, k, k, k), 
    -- Row 12
    (k, b, m, m, m, m, b, m, m, b, m, m, m, m, b, s, m, b, s, s, s, b, m, m, m, b, m, b, k, k, k, k), 
    -- Row 13
    (k, b, m, m, m, m, b, m, m, b, m, m, m, b, s, s, m, b, s, s, b, b, b, m, m, b, b, k, k, k, k, k), 
    -- Row 14
    (k, b, m, m, m, m, b, m, b, b, m, m, b, b, b, b, b, s, s, s, b, w, b, m, m, b, b, k, k, k, k, k), 
    -- Row 15
    (k, b, m, m, m, m, b, m, b, b, b, b, w, b, b, s, b, s, s, s, d, w, b, g, g, b, k, k, k, k, k, k), 
    -- Row 16
    (k, b, m, m, m, m, b, b, b, b, r, m, w, w, d, s, s, s, s, s, m, w, b, m, b, b, b, b, w, b, k, k), 
    -- Row 17
    (k, b, m, m, m, m, b, b, m, b, r, m, w, d, m, s, s, s, s, s, d, s, b, m, b, b, l, b, b, l, b, k), 
    -- Row 18
    (k, b, m, m, m, m, b, k, b, b, r, m, s, d, d, s, s, s, s, s, s, s, b, b, m, b, l, b, l, l, b, k), 
    -- Row 19
    (k, b, m, m, m, m, b, k, k, b, m, m, s, s, s, s, s, s, s, s, s, b, b, m, m, b, l, l, l, b, k, k), 
    -- Row 20
    (k, b, m, m, m, m, b, k, k, k, b, b, m, s, s, s, s, s, s, b, b, b, m, m, m, b, l, l, b, k, k, k), 
    -- Row 21
    (k, b, m, m, m, m, m, b, k, k, k, k, b, g, g, g, g, g, m, g, s, b, m, m, b, w, l, b, k, k, k, k), 
    -- Row 22
    (k, b, m, m, m, m, m, b, k, k, k, b, s, s, g, g, g, g, m, g, b, m, b, b, w, w, b, k, k, k, k, k), 
    -- Row 23
    (k, b, m, m, m, m, m, b, k, k, b, m, m, b, g, g, g, g, m, g, b, b, b, w, w, b, b, k, k, k, k, k), 
    -- Row 24
    (k, b, m, m, m, m, m, b, k, b, b, b, b, m, m, g, g, m, b, m, g, b, s, w, b, m, m, b, k, k, k, k), 
    -- Row 25
    (k, b, m, m, m, m, m, m, b, b, b, b, b, b, b, m, m, b, b, b, m, b, w, b, m, m, m, b, k, k, k, k), 
    -- Row 26
    (k, k, b, m, m, m, m, m, b, b, s, b, b, b, b, b, b, b, b, b, b, m, b, m, m, m, m, b, k, k, k, k), 
    -- Row 27
    (k, k, b, m, m, m, m, m, b, k, b, b, m, m, m, m, m, m, m, m, m, b, b, m, m, m, m, b, k, k, k, k), 
    -- Row 28
    (k, k, k, b, m, m, m, m, b, k, k, k, b, b, b, b, b, b, b, b, b, w, w, b, m, m, b, k, k, k, k, k), 
    -- Row 29
    (k, k, k, k, b, m, m, b, k, k, k, b, b, b, b, k, k, k, b, m, b, k, k, k, b, b, k, k, k, k, k, k), 
    -- Row 30
    (k, k, k, k, k, b, b, k, k, k, k, b, m, b, k, k, k, k, k, b, b, k, k, k, k, k, k, k, k, k, k, k), 
    -- Row 31
    (k, k, k, k, k, k, k, k, k, k, k, k, b, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k, k)
);

-- Monster sprite (32x32)
constant MONSTER : pixel := (
    -- Row 0
    (p, p, c, p, p, c, p, p, c, p, p, p, b, b, b, b, b, b, b, b, p, p, p, c, p, p, c, p, p, c, p, p), 
    -- Row 1
    (c, p, p, c, p, p, c, p, p, b, b, b, w, w, e, w, w, w, w, w, b, b, b, p, p, c, p, p, c, p, p, c), 
    -- Row 2
    (p, c, p, p, c, p, p, b, b, w, w, w, w, w, e, w, w, w, w, w, w, e, w, b, b, p, p, c, p, p, c, p), 
    -- Row 3
    (p, p, c, p, p, b, b, w, e, w, w, w, w, w, w, e, w, w, w, w, w, e, w, w, w, b, b, p, p, c, p, p), 
    -- Row 4
    (p, b, b, p, b, w, w, w, e, w, w, w, w, w, w, w, e, w, w, w, w, w, e, w, w, w, w, b, p, b, b, p), 
    -- Row 5
    (b, b, g, b, w, w, w, w, w, e, w, w, w, w, w, w, w, e, w, w, w, w, e, e, w, w, w, w, b, g, b, b), 
    -- Row 6
    (g, g, g, b, w, w, w, w, w, e, w, w, w, w, w, w, e, w, w, w, w, w, w, e, w, w, w, w, b, g, g, g), 
    -- Row 7
    (g, g, b, w, w, w, w, w, w, w, e, r, r, r, r, r, r, r, r, r, r, w, e, w, w, w, w, e, w, b, g, g), 
    -- Row 8
    (g, g, b, e, w, w, w, w, w, w, r, r, r, r, r, r, r, r, r, r, r, r, w, w, w, w, e, e, w, b, g, g), 
    -- Row 9
    (g, b, w, w, e, w, w, w, w, r, r, r, r, r, r, r, r, r, r, r, r, r, r, w, w, w, e, w, w, w, b, g), 
    -- Row 10
    (g, b, w, w, w, e, e, e, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, w, e, w, w, w, w, b, g), 
    -- Row 11
    (g, b, w, w, w, w, w, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, w, w, w, w, w, b, g), 
    -- Row 12
    (b, e, w, w, w, w, w, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, w, w, w, e, e, w, b), 
    -- Row 13
    (b, w, e, w, e, e, e, r, r, r, r, r, r, r, b, b, b, b, r, r, r, r, r, r, r, e, w, e, w, w, e, b), 
    -- Row 14
    (b, w, w, e, w, w, w, r, r, r, r, r, r, b, b, b, b, b, b, r, r, r, r, r, r, w, e, w, w, w, w, b), 
    -- Row 15
    (b, w, w, w, w, w, w, r, r, r, r, r, r, b, b, b, b, b, b, r, r, r, r, r, r, w, w, w, w, w, w, b), 
    -- Row 16
    (b, w, w, w, w, w, w, r, r, r, r, r, r, b, b, b, b, b, b, r, r, r, r, r, r, w, w, w, w, e, e, b), 
    -- Row 17
    (b, w, e, e, w, w, e, r, r, r, r, r, r, b, b, b, b, b, b, r, r, r, r, r, r, w, e, e, e, w, w, b), 
    -- Row 18
    (b, e, w, w, e, e, w, r, r, r, r, r, r, r, b, b, b, b, r, r, r, r, r, r, r, e, w, w, w, w, w, b), 
    -- Row 19
    (b, w, w, w, w, w, w, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, w, w, w, w, w, w, b), 
    -- Row 20
    (g, b, w, w, w, w, w, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, w, w, w, w, w, b, g), 
    -- Row 21
    (g, b, w, w, w, w, e, w, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, r, w, e, e, w, w, w, b, g), 
    -- Row 22
    (g, b, w, w, w, e, w, w, w, r, r, r, r, r, r, r, r, r, r, r, r, r, r, w, w, w, w, e, e, w, b, g), 
    -- R0w 23
    (g, g, b, w, e, w, w, w, w, w, r, r, r, r, r, r, r, r, r, r, r, r, e, w, w, w, w, w, w, b, g, g), 
    -- Row 24
    (g, g, b, w, e, w, w, w, w, e, w, r, r, r, r, r, r, r, r, r, r, w, e, w, w, w, w, w, w, b, g, g), 
    -- Row 25
    (g, g, g, b, w, w, w, w, w, e, w, w, w, w, e, w, w, w, w, e, w, w, w, e, w, w, w, w, b, g, g, g), 
    -- Row 26
    (b, b, g, b, w, w, w, w, e, w, w, w, w, e, w, w, w, w, e, w, w, w, w, w, e, e, w, w, b, g, b, b), 
    -- Row 27
    (p, b, b, p, b, w, w, w, e, w, w, w, w, e, w, w, w, w, w, e, w, w, w, w, w, w, e, b, p, b, b, p), 
    -- Row 28
    (p, p, c, p, p, b, b, e, w, w, w, w, w, w, e, w, w, w, w, w, e, w, w, w, w, b, b, p, p, c, p, p), 
    -- Row 29
    (p, c, p, p, c, p, p, b, b, w, w, w, w, w, e, w, w, w, w, w, e, w, w, b, b, p, p, c, p, p, c, p), 
    -- Row 30
    (c, p, p, c, p, p, c, p, p, b, b, b, w, e, w, w, w, w, w, w, b, b, b, p, p, c, p, p, c, p, p, c), 
    -- Row 31
    (p, p, c, p, p, c, p, p, c, p, p, p, b, b, b, b, b, b, b, b, p, p, p, c, p, p, c, p, p, c, p, p)
);

-- component declaration
component clock_divider is
    generic (N : integer);
    port (
        clk: in std_logic;
        clk_out: out std_logic
    );
end component;

-- Add a 1Hz clock for monster movement
signal clk1Hz : std_logic;

-- Add signal for monster movement enable (toggle)
signal monster_move_enable : std_logic := '0';

-- Select current maze, start, and end based on level
function get_maze(level: integer) return MAZE_ARRAY is
begin
    if level = 1 then
        return MAZE1;
    elsif level = 2 then
        return MAZE2;
    else
        return MAZE3;
    end if;
end function;

signal current_maze : MAZE_ARRAY;
signal start_row, start_col, end_row, end_col : integer;

-- Monster type and array for monster positions

type MONSTER_COORD is record
    row : integer;
    col : integer;
end record;

type MONSTER_ARRAY is array (natural range <>) of MONSTER_COORD;

signal MONSTERS : MONSTER_ARRAY(0 to 8) := (
    (row => 3, col => 3),     -- horizontal
    (row => 5, col => 18),    -- horizontal
    (row => 8, col => 13),    -- horizontal
    (row => 14, col => 26),   -- horizontal
    (row => 10, col => 4),    -- horizontal
    (row => 2, col => 7),     -- vertical
    (row => 6, col => 20),    -- vertical
    (row => 12, col => 10),   -- vertical
    (row => 16, col => 25)    -- vertical
);

-- Monster coordinates received from Vitis
signal MONSTERS_NEW : MONSTER_ARRAY(0 to 8) := (
    (row => 3, col => 3),   
    (row => 5, col => 18),    
    (row => 8, col => 13),    
    (row => 14, col => 26),   
    (row => 10, col => 4),    
    (row => 2, col => 7),     
    (row => 6, col => 20),    
    (row => 12, col => 10),   
    (row => 16, col => 25)    
);

--type VISIBLE_ARRAY is array (0 to MAZE_HEIGHT-1, 0 to MAZE_WIDTH-1) of std_logic;
signal VISIBLE : MAZE_ARRAY := (others => (others => '0'));

signal LIT_ROW : integer range 0 to MAZE_HEIGHT := 2; 
signal LIT_COL : integer range 0 to MAZE_WIDTH := 0; 

signal LIT_ROW_NEW : integer range 0 to MAZE_HEIGHT := MAZE_HEIGHT; 
signal LIT_COL_NEW : integer range 0 to MAZE_WIDTH := MAZE_WIDTH;

begin

-- generate 50MHz clock
comp_clk50MHz : clock_divider
    generic map(N => 1) port map(clk, clk50MHz);

-- 100Hz clock for responsive but debounced input (10ms tick)
comp_clk100Hz: clock_divider
    generic map(N => 500000) port map(clk, clk100Hz); -- 50M/500k = 100Hz

-- 1Hz clock for monster movement (example: 50M/50M = 1Hz)
comp_clk1Hz: clock_divider
    generic map(N => 50000000) port map(clk, clk1Hz);

-- horizontal counter
hcount_proc: process (clk50MHz)
begin
    if (rising_edge(clk50MHz)) then
        if (hcount = H_TOTAL) then
            hcount <= 0;
        else
            hcount <= hcount + 1;
        end if;
    end if;
end process hcount_proc;

-- vertical counter
vcount_proc: process (clk50MHz)
begin
    if (rising_edge(clk50MHz)) then
        if (hcount = H_TOTAL) then
            if (vcount = V_TOTAL) then
                vcount <= 0;
            else
                vcount <= vcount + 1;
            end if;
        end if;
    end if;
end process vcount_proc;

-- generate hsync
hsync_gen_proc : process (hcount) 
begin
    if (hcount < H_SYNC) then
        hsync<= '0';
    else
        hsync<= '1';
    end if;
end process hsync_gen_proc;

--generate vsync
vsync_gen_proc : process (vcount)
begin
    if (vcount < V_SYNC) then
        vsync<= '0';
    else
        vsync<= '1';
    end if;
end process vsync_gen_proc;

-- RGB output logic, including maze, monsters, player, start/end cells, GAME OVER message
data_output_proc : process (hcount, vcount, game_over)
    variable maze_x : integer;
    variable maze_y : integer;
    variable pixel_x : integer;
    variable pixel_y : integer;
    variable show_monster : boolean;
    variable i : integer;
    -- For game over message
    variable msg_x : integer;
    variable msg_y : integer;
begin
    -- Default: blanking area
    red   <= "0000";
    green <= "0000";
    blue  <= "0000";
    show_monster := false;

    -- If game over, show the message using cells
    if game_over = '1' then
        -- Draw message for the entire maze area (30x18)
        if ((hcount >= H_START) and (hcount < H_START + MAZE_WIDTH*CELL_SIZE) and
            (vcount >= V_START) and (vcount < V_START + MAZE_HEIGHT*CELL_SIZE)) then

            msg_x := (hcount - H_START) / CELL_SIZE;
            msg_y := (vcount - V_START) / CELL_SIZE;

            if msg_x >= 0 and msg_x < MSG_COLS and msg_y >= 0 and msg_y < MSG_ROWS then
                if GAME_OVER_MSG(msg_y, msg_x) = '1' then
                    -- Message letter cell (bright yellow)
                    red   <= "1111";
                    green <= "0111";
                    blue  <= "1111";
                else
                    -- Message background cell (black)
                    red   <= "0100";
                    green <= "1111";
                    blue  <= "1111";
                end if;
            end if;
        end if;
        -- Everything else remains black
    else
        -- Only process pixels that are within the exact maze area
        if ((hcount >= H_START) and (hcount < H_START + MAZE_WIDTH*CELL_SIZE) and
            (vcount >= V_START) and (vcount < V_START + MAZE_HEIGHT*CELL_SIZE)) then

            -- Calculate which maze cell we're in for the current pixel
            maze_x := (hcount - H_START) / CELL_SIZE;
            maze_y := (vcount - V_START) / CELL_SIZE;
            
            pixel_x := (hcount - H_START) mod CELL_SIZE; -- pixel x-coordinate in cell
            pixel_y := (vcount - V_START) mod CELL_SIZE; -- pixel y-coordinate in cell
            
            if (VISIBLE(maze_y, maze_x) = '0') then
                red <= "0000";
                green <= "0000";
                blue <= "0000";
            else
                -- Draw monsters on top (blue)
                for i in 0 to MONSTERS'length-1 loop
                    if (maze_y = MONSTERS(i).row and maze_x = MONSTERS(i).col) then
                        -- Within monster cell, show blue
                        if (((hcount - H_START) mod CELL_SIZE) < PLAYER_SIZE) and (((vcount - V_START) mod CELL_SIZE) < PLAYER_SIZE) then
--                            red   <= "0000";
--                            green <= "0000";
--                            blue  <= "1111";
                            if (MONSTER(pixel_y, pixel_x) = p) then
                                red   <= "1111";
                                green <= "0000";
                                blue  <= "1111";
                            elsif (MONSTER(pixel_y, pixel_x) = c) then
                                red   <= "0100";
                                green <= "0000";
                                blue  <= "0000";
                            elsif (MONSTER(pixel_y, pixel_x) = b) then
                                red   <= "0000";
                                green <= "0000";
                                blue  <= "0000";
                            elsif (MONSTER(pixel_y, pixel_x) = w) then
                                red   <= "1111";
                                green <= "1111";
                                blue  <= "1111";
                            elsif (MONSTER(pixel_y, pixel_x) = e) then
                                red   <= "1000";
                                green <= "0000";
                                blue  <= "0000";
                            elsif (MONSTER(pixel_y, pixel_x) = g) then
                                red   <= "1001";
                                green <= "1001";
                                blue  <= "1001";
                            elsif (MONSTER(pixel_y, pixel_x) = r) then
                                red   <= "1111";
                                green <= "0000";
                                blue  <= "0000";
                            end if;
                            show_monster := true;
                        end if;
                    end if;
                end loop;
    
                if not show_monster then
                    -- Player : draw on top of maze, except if monster present
                    if (maze_y = player_row and maze_x = player_col) then
                        -- Within player square
                        if (((hcount - H_START) mod CELL_SIZE) < PLAYER_SIZE) and (((vcount - V_START) mod CELL_SIZE) < PLAYER_SIZE) then
--                            red   <= "1111";
--                            green <= "0000";
--                            blue  <= "1111";
                            if (PLAYER(pixel_y, pixel_x) = k) then
                                red   <= "1001";
                                green <= "0011";
                                blue  <= "0000";
                            elsif (PLAYER(pixel_y, pixel_x) = b) then
                                red   <= "0000";
                                green <= "0000";
                                blue  <= "0000";
                            elsif (PLAYER(pixel_y, pixel_x) = w) then
                                red   <= "1111";
                                green <= "1111";
                                blue  <= "1111";
                            elsif (PLAYER(pixel_y, pixel_x) = g) then
                                red   <= "1000";
                                green <= "1000";
                                blue  <= "1000";
                            elsif (PLAYER(pixel_y, pixel_x) = r) then
                                red   <= "1111";
                                green <= "0000";
                                blue  <= "0000";
                            elsif (PLAYER(pixel_y, pixel_x) = l) then
                                red   <= "1100";
                                green <= "1111";
                                blue  <= "1100";
                            elsif (PLAYER(pixel_y, pixel_x) = m) then
                                red   <= "0000";
                                green <= "1101";
                                blue  <= "1111";
                            elsif (PLAYER(pixel_y, pixel_x) = d) then
                                red   <= "0000";
                                green <= "1001";
                                blue  <= "1111";
                            elsif (PLAYER(pixel_y, pixel_x) = s) then
                                red   <= "1111";
                                green <= "1101";
                                blue  <= "1011";
                            end if;
                        end if;
                    -- Start 
                    elsif (maze_y = START_ROW and maze_x = START_COL) then
                        red   <= "0000";
                        green <= "1111";
                        blue  <= "0000";
                    -- End 
                    elsif (maze_y = END_ROW and maze_x = END_COL) then
                        red   <= "1111";
                        green <= "0000";
                        blue  <= "0000";
                    -- Walls/paths
                    elsif (maze_x >= 0 and maze_x < MAZE_WIDTH and maze_y >= 0 and maze_y < MAZE_HEIGHT) then
                        if (current_maze(maze_y, maze_x) = '1') then
--                            -- Wall: black
--                            red   <= "0000";
--                            green <= "0000";
--                            blue  <= "0000";
                            if (WALLS(pixel_y, pixel_x) = gap) then
                                red   <= "0100";
                                green <= "0100";
                                blue  <= "0100";
                            elsif (WALLS(pixel_y, pixel_x) = b5) then
                                red   <= "0111";
                                green <= "0111";
                                blue  <= "0111";
                            elsif (WALLS(pixel_y, pixel_x) = b4) then
                                red   <= "1000";
                                green <= "1000";
                                blue  <= "1000";
                            elsif (WALLS(pixel_y, pixel_x) = b3) then
                                red   <= "1001";
                                green <= "1001";
                                blue  <= "1001";
                            elsif (WALLS(pixel_y, pixel_x) = b2) then
                                red   <= "1010";
                                green <= "1010";
                                blue  <= "1010";
                            elsif (WALLS(pixel_y, pixel_x) = b1) then
                                red   <= "1011";
                                green <= "1011";
                                blue  <= "1011";
                            end if;
                        else
--                             Path: white
--                            red   <= "1111";
--                            green <= "1111";
--                            blue  <= "1111";
                            if (PATHS(pixel_y, pixel_x) = dark) then
                                red   <= "0011";
                                green <= "0000";
                                blue  <= "0000";
                            elsif (PATHS(pixel_y, pixel_x) = mid) then
                                red   <= "0111";
                                green <= "0000";
                                blue  <= "0000";
                            elsif (PATHS(pixel_y, pixel_x) = light) then
                                red   <= "1011";
                                green <= "0101";
                                blue  <= "0000";
                            elsif (PATHS(pixel_y, pixel_x) = pebble) then
                                red   <= "1111";
                                green <= "1010";
                                blue  <= "0100";
                            elsif (PATHS(pixel_y, pixel_x) = ground) then
                                red   <= "1001";
                                green <= "0011";
                                blue  <= "0000";
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end if;
end process data_output_proc;

-- Movement process: move ONCE per button press (rising edge), debounce by checking at 100Hz
movement_proc : process(clk100Hz)
    variable next_row, next_col: integer;
    variable any_button_pressed : std_logic;
    variable touched_monster : boolean;
    variable i : integer;
begin
    if rising_edge(clk100Hz) then
        -- Only allow movement if not game over
        if game_over = '0' then
            -- Detect rising edge: current is '1', previous is '0'
            -- Up
            if (BTNU = '1' and prev_BTNU = '0') then
                next_row := player_row - 1;
                next_col := player_col;
                if (next_row >= 0 and next_row < MAZE_HEIGHT) then
                    if (current_maze(next_row, next_col) = '0') then
                        player_row <= next_row;
                    end if;
                end if;
            -- Down
            elsif (BTND = '1' and prev_BTND = '0') then
                next_row := player_row + 1;
                next_col := player_col;
                if (next_row >= 0 and next_row < MAZE_HEIGHT) then
                    if (current_maze(next_row, next_col) = '0') then
                        player_row <= next_row;
                    end if;
                end if;
            -- Left
            elsif (BTNL = '1' and prev_BTNL = '0') then
                next_row := player_row;
                next_col := player_col - 1;
                if (next_col >= 0 and next_col < MAZE_WIDTH) then
                    if (current_maze(next_row, next_col) = '0') then
                        player_col <= next_col;
                    end if;
                end if;
            -- Right
            elsif (BTNR = '1' and prev_BTNR = '0') then
                next_row := player_row;
                next_col := player_col + 1;
                if (next_col >= 0 and next_col < MAZE_WIDTH) then
                    if (current_maze(next_row, next_col) = '0') then
                        player_col <= next_col;
                    end if;
                end if;
            end if;
            -- Monster collision detection
            touched_monster := false;
            for i in 0 to MONSTERS'length-1 loop
                if (player_row = MONSTERS(i).row) and (player_col = MONSTERS(i).col) then
                                    touched_monster := true;
                end if;
            end loop;
            if touched_monster then
                game_over <= '1';
            end if;
            -- After movement, if at end cell, advance level or repeat game
            if (player_row = end_row and player_col = end_col) then
                if level < 3 then
                    level <= level + 1;
                    player_row <= START_ROW_ARR(level+1);
                    player_col <= START_COL_ARR(level+1);
                    game_over <= '0';
                else
                    level <= 1;
                    player_row <= START_ROW_ARR(1);
                    player_col <= START_COL_ARR(1);
                    game_over <= '0';
                end if;
            end if;
        end if;
        -- Toggle monster movement enable on any button rising edge
        any_button_pressed := '0';
        if (BTNU = '1' and prev_BTNU = '0') then
            any_button_pressed := '1';
        end if;
        if (BTND = '1' and prev_BTND = '0') then
            any_button_pressed := '1';
        end if;
        if (BTNL = '1' and prev_BTNL = '0') then
            any_button_pressed := '1';
        end if;
        if (BTNR = '1' and prev_BTNR = '0') then
            any_button_pressed := '1';
        end if;
        if any_button_pressed = '1' then
            if monster_move_enable = '0' then
                monster_move_enable <= '1';
            else
                monster_move_enable <= '0';
            end if;
        end if;
        -- Update previous button states
        prev_BTNU <= BTNU;
        prev_BTND <= BTND;
        prev_BTNL <= BTNL;
        prev_BTNR <= BTNR;
    end if;
end process movement_proc;

-- Monster movement process: monsters move continuously at 1Hz (no longer depend on button or monster_move_enable)
monster_movement_proc : process(clk1Hz)
    variable i : integer;
begin
    if rising_edge(clk1Hz) then
        for i in 0 to 8 loop
            MONSTERS(i).col <= MONSTERS_NEW(i).col;
            MONSTERS(i).row <= MONSTERS_NEW(i).row;
        end loop;
    end if;
end process monster_movement_proc;

visibility_update_proc : process(clk1Hz, LIT_ROW, LIT_COL)
    variable row, col, i, j : integer;
begin
    for row in 0 to MAZE_HEIGHT-1 loop
        for col in 0 to MAZE_WIDTH-1 loop
            if(abs(row - LIT_ROW) <= 2) and (abs(col - LIT_COL) <= 2) then
                VISIBLE(row, col) <= '1';
            else
                VISIBLE(row, col) <= '0';
            end if;
        end loop;
    end loop;
    if rising_edge(clk1Hz) then
--        if (LIT_COL < 29) then
--            LIT_COL <= LIT_COL + 1;
--        else
--            LIT_COL <= 0;
--        end if;
        LIT_COL <= LIT_COL_NEW;
        LIT_ROW <= LIT_ROW_NEW;
    end if;
end process visibility_update_proc;

-- Update current maze and positions based on level
current_maze <= get_maze(level);
start_col <= START_COL_ARR(level);
start_row <= START_ROW_ARR(level);
end_col   <= END_COL_ARR(level);
end_row   <= END_ROW_ARR(level);

    
--    s_slv_reg0 <= (C_S00_AXI_DATA_WIDTH-1 downto 1 => '0') & BTNU;
--    s_slv_reg1 <= (C_S00_AXI_DATA_WIDTH-1 downto 1 => '0') & BTND;
--    s_slv_reg2 <= (C_S00_AXI_DATA_WIDTH-1 downto 1 => '0') & BTNL;
--    s_slv_reg3 <= (C_S00_AXI_DATA_WIDTH-1 downto 1 => '0') & BTNR;
    
--    MONSTERS_NEW(0).col <= to_integer(unsigned(s_slv_reg0 (4 downto 0)));
--    MONSTERS_NEW(0).row <= to_integer(unsigned(s_slv_reg0 (9 downto 5)));
--    MONSTERS_NEW(1).col <= to_integer(unsigned(s_slv_reg0 (15 downto 11)));
--    MONSTERS_NEW(1).row <= to_integer(unsigned(s_slv_reg0 (20 downto 16)));
--    MONSTERS_NEW(2).col <= to_integer(unsigned(s_slv_reg0 (26 downto 22)));
--    MONSTERS_NEW(2).row <= to_integer(unsigned(s_slv_reg0 (31 downto 27)));
--    MONSTERS_NEW(3).col <= to_integer(unsigned(s_slv_reg1 (4 downto 0)));
--    MONSTERS_NEW(3).row <= to_integer(unsigned(s_slv_reg1 (9 downto 5)));
--    MONSTERS_NEW(4).col <= to_integer(unsigned(s_slv_reg1 (15 downto 11)));
--    MONSTERS_NEW(4).row <= to_integer(unsigned(s_slv_reg1 (20 downto 16)));
--    MONSTERS_NEW(5).col <= to_integer(unsigned(s_slv_reg1 (26 downto 22)));
--    MONSTERS_NEW(5).row <= to_integer(unsigned(s_slv_reg1 (31 downto 27)));
--    MONSTERS_NEW(6).col <= to_integer(unsigned(s_slv_reg2 (4 downto 0)));
--    MONSTERS_NEW(6).row <= to_integer(unsigned(s_slv_reg2 (9 downto 5)));
--    MONSTERS_NEW(7).col <= to_integer(unsigned(s_slv_reg2 (15 downto 11)));
--    MONSTERS_NEW(7).row <= to_integer(unsigned(s_slv_reg2 (20 downto 16)));
--    MONSTERS_NEW(8).col <= to_integer(unsigned(s_slv_reg2 (26 downto 22)));
--    MONSTERS_NEW(8).row <= to_integer(unsigned(s_slv_reg2 (31 downto 27)));

--    LIT_COL_NEW <= to_integer(unsigned(s_slv_reg3 (4 downto 0)));
--    LIT_ROW_NEW <= to_integer(unsigned(s_slv_reg3 (9 downto 5)));

end game_display_arch;
