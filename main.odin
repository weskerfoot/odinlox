#+feature dynamic-literals
package main
import "base:runtime"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:sys/linux"
import "core:sys/posix"
import "core:os"
import "core:bufio"
import "core:unicode"
import "core:strconv"

hadError : bool = false

TokenType :: enum {
  // Single-character tokens.
  LEFT_PAREN, RIGHT_PAREN, LEFT_BRACE, RIGHT_BRACE,
  COMMA, DOT, MINUS, PLUS, SEMICOLON, SLASH, STAR,

  // One or two character tokens.
  BANG, BANG_EQUAL,
  EQUAL, EQUAL_EQUAL,
  GREATER, GREATER_EQUAL,
  LESS, LESS_EQUAL,

  // Literals.
  IDENTIFIER, STRING, NUMBER,

  // Keywords.
  AND, CLASS, ELSE, FALSE, FUN, FOR, IF, NIL, OR,
  PRINT, RETURN, SUPER, THIS, TRUE, VAR, WHILE,

  EOF
}

keywords := map[string]int{
  "and" = cast(int)TokenType.AND,
  "class" = cast(int)TokenType.CLASS,
  "else" = cast(int)TokenType.ELSE,
  "false" = cast(int)TokenType.FALSE,
  "for" = cast(int)TokenType.FOR,
  "fun" = cast(int)TokenType.FUN,
  "if"  = cast(int)TokenType.IF,
  "nil" = cast(int)TokenType.NIL,
  "or"  = cast(int)TokenType.OR,
  "print" = cast(int)TokenType.PRINT,
  "return" = cast(int)TokenType.RETURN,
  "super" = cast(int)TokenType.SUPER,
  "this" = cast(int)TokenType.THIS,
  "true" = cast(int)TokenType.TRUE,
  "var" = cast(int)TokenType.VAR,
  "while" = cast(int)TokenType.WHILE
}

Literal :: union {
  f64,
  string
}

Token :: struct {
  type : TokenType,
  lexeme_start : int,
  lexeme_end : int,
  literal : Literal,
  line : int
}

tokens : #soa[dynamic]Token

error :: proc(line : int, message : string) {
  report(line, "", message)
}

report :: proc(line : int, where_from : string, message : string) {
  fmt.println("[line ", line, "] Error", where_from, ": ", message)
  hadError = true
}

isDigit :: proc(c : rune) -> bool {
  return c >= '0' && c <= '9'
}

isAlpha :: proc(c : rune) -> bool {
  return (c >= 'a' && c <= 'z') ||
         (c >= 'A' && c <= 'Z') ||
         c == '_';
}

isAlphaNumeric :: proc(c : rune) -> bool {
  return isAlpha(c) || isDigit(c)
}

addToken_simple :: proc(token_type : TokenType,
                        start: int,
                        end: int,
                        line_no: int) {
  token : Token = {token_type, start, end, 0, line_no}
  append(&tokens, token)
  return
}

addToken_literal :: proc(token_type : TokenType,
                         start: int,
                         end: int,
                         line_no: int,
                         literal: Literal) {
  token : Token = {token_type, start, end, literal, line_no}
  append(&tokens, token)
  return
}

addToken :: proc{addToken_simple, addToken_literal}

peek :: proc(source : string, current : int) -> rune {
  if current >= len(source) {
    return rune(0)
  }
  return rune(source[current])
}

peekNext :: proc(source : string, current : int) -> rune {
  if current + 1 >= len(source) {
    return rune(0)
  }
  return rune(source[current + 1])
}

match :: proc(expected : rune,
              current : ^int,
              source : string) -> bool {
  if current^ >= len(source) {
    return false
  }
  if rune(source[current^]) != expected {
    return false
  }
  current^ += 1
  return true
}

string_tokenize :: proc(source : string,
                        current : ^int,
                        line : ^int) {
  start : int = current^
  for peek(source, current^) != '"' && !(current^ >= len(source)) {
    if peek(source, current^) == '\n' {
      line^ += 1
    }
    current^ += 1
  }
  if current^ >= len(source) {
    error(line^, "Unterminated string")
    return
  }
  string_lit := transmute(string)source[start:current^]
  addToken(TokenType.STRING, start, current^, line^, string_lit)
  current^ += 1
}

number_tokenize :: proc(source : string,
                        current : ^int,
                        line : ^int) {
  start : int = current^
  for isDigit(peek(source, current^)) {
    current^ += 1
  }
  if peek(source, current^) == '.' && isDigit(peekNext(source, current^)) {
    current^ += 1
    for isDigit(peek(source, current^)) {
      current^ += 1
    }
  }
  lit_result_length : int
  lit_result, result_ok := strconv.parse_f64(source[start-1:current^], &lit_result_length)
  if result_ok {
    addToken(TokenType.NUMBER, start-1, current^, line^, lit_result)
  }
  else {
    error(line^, "Failed to parse number literal")
  }
}

ident_tokenize :: proc(source : string,
                       current : ^int,
                       line : ^int) {
  start : int = current^
  for isAlphaNumeric(peek(source, current^)) {
    current^ += 1
  }

  ident_lit := transmute(string)source[start-1:current^]
  keyword_type, keyword_ok := &keywords[ident_lit]
  if keyword_ok {
    addToken(cast(TokenType)keyword_type^, start-1, current^, line^)
  }
  else {
    addToken(TokenType.IDENTIFIER, start-1, current^, line^)
  }
}

scanTokens :: proc(source : string) {
  current : int = 0
  start : int = 0
  line : int = 1
  for current < len(source) {
    c := rune(source[current])
    current += 1
    switch c {
      case '(': addToken(TokenType.LEFT_PAREN, current-1, current, line)
      case ')': addToken(TokenType.RIGHT_PAREN, current-1, current, line)
      case '{': addToken(TokenType.LEFT_BRACE, current-1, current, line)
      case '}': addToken(TokenType.RIGHT_BRACE, current-1, current, line)
      case ',': addToken(TokenType.COMMA, current-1, current, line)
      case '.': addToken(TokenType.DOT, current-1, current, line)
      case '-': addToken(TokenType.MINUS, current-1, current, line)
      case '+': addToken(TokenType.PLUS, current-1, current, line)
      case ';': addToken(TokenType.SEMICOLON, current-1, current, line)
      case '*': addToken(TokenType.STAR, current-1, current, line)
      case '!':
        addToken(TokenType.BANG_EQUAL if match('=', &current, source) else TokenType.BANG, current-1, current, line)
      case '=':
        addToken(TokenType.EQUAL_EQUAL if match('=', &current, source) else TokenType.EQUAL, current-1, current, line)
      case '<':
        addToken(TokenType.LESS_EQUAL if match('=', &current, source) else TokenType.LESS, current-1, current, line)
      case '>':
        addToken(TokenType.GREATER_EQUAL if match('=', &current, source) else TokenType.GREATER, current-1, current, line)
      case '/':
        if match('/', &current, source) {
          for peek(source, current) != rune('\n') && !(current >= len(source)) {
            current += 1
          }
        }
        else {
          addToken(TokenType.SLASH, current-1, current, line)
        }
      case '"':
        string_tokenize(source, &current, &line)
        break
      case ' ':
      case '\r':
      case '\t':
        break
      case '\n':
        line += 1
        break
      case:
        if isDigit(c) {
          number_tokenize(source, &current, &line)
        }
        else if isAlpha(c) {
          ident_tokenize(source, &current, &line)
        }
        else {
          error(line, "Unexpected character")
        }
        break
    }
  }
}

run :: proc(source : string) {
  scanTokens(source)
  for token in tokens {
    fmt.println(token)
  }
}

runFile :: proc(filename : string) {
  data, err := os.read_entire_file_from_path(filename, context.allocator)
  defer if len(data) > 0 { delete(data) }
  source := string(data)
  run(source)
}

runPrompt :: proc() {
	r := bufio.Reader{}
	buffer: [512]byte
	bufio.reader_init_with_buf(&r, os.to_stream(os.stdin), buffer[:])
	for {
    fmt.print("> ")
		defer free_all(context.temp_allocator)
    defer clear(&tokens)
		// read line till \n, note that \n is included in the return
		line, err := bufio.reader_read_string(&r, '\n', context.temp_allocator)
		line = strings.trim_right(line, "\r")
		if err != nil {
			// EOF reached
			break
		}
    run(line)
    hadError = false
	}
	bufio.reader_destroy(&r)
  return
}

main :: proc() {
  input: [dynamic]u8
  if len(os.args) > 2 {
    fmt.println("Usage: odinlox [script]")
    os.exit(1)
  }
  else if len(os.args) == 2 {
    runFile(os.args[1])
  }
  else {
    runPrompt()
  }

  test_string: string = string(input[:])
  fmt.println(test_string)

  if hadError {
    os.exit(65)
  }
}
