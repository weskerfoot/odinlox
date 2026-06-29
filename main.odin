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

Literal :: union {
  int,
  string,
}

Token :: struct {
  type : TokenType,
  lexeme_start : int,
  lexeme_end : int,
  literal : Literal,
  line : int
}

error :: proc(line : int, message : string) {
  report(line, "", message)
}

report :: proc(line : int, where_from : string, message : string) {
  fmt.println("[line ", line, "] Error", where_from, ": ", message)
  hadError = true
}

addToken_simple :: proc(token_type : TokenType,
                        tokens : ^[dynamic]Token,
                        start: int,
                        end: int,
                        line_no: int) {
  token : Token = {token_type, start, end, 0, line_no}
  append(tokens, token)
  return
}

addToken_literal :: proc(token_type : TokenType,
                         tokens : ^[dynamic]Token,
                         start: int,
                         end: int,
                         line_no: int,
                         literal: Literal) {
  token : Token = {token_type, start, end, literal, line_no}
  append(tokens, token)
  return
}

addToken :: proc{addToken_simple, addToken_literal}

peek :: proc(source : string, current : int) -> rune {
  if current >= len(source) {
    return rune(0)
  }
  return rune(source[current])
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
                        line : ^int,
                        tokens : ^[dynamic]Token) {
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
  addToken(TokenType.STRING, tokens, start, current^-1, line^)
  current^ += 1
}

scanTokens :: proc(source : string, tokens : ^[dynamic]Token) {
  current : int = 0
  start : int = 0
  line : int = 1
  for current < len(source) {
    c := rune(source[current])
    current += 1
    switch c {
      case '(': addToken(TokenType.LEFT_PAREN, tokens, current, current+1, line)
      case ')': addToken(TokenType.RIGHT_PAREN, tokens, current, current+1, line)
      case '{': addToken(TokenType.LEFT_BRACE, tokens, current, current+1, line)
      case '}': addToken(TokenType.RIGHT_BRACE, tokens, current, current+1, line)
      case ',': addToken(TokenType.COMMA, tokens, current, current+1, line)
      case '.': addToken(TokenType.DOT, tokens, current, current+1, line)
      case '-': addToken(TokenType.MINUS, tokens, current, current+1, line)
      case '+': addToken(TokenType.PLUS, tokens, current, current+1, line)
      case ';': addToken(TokenType.SEMICOLON, tokens, current, current+1, line)
      case '*': addToken(TokenType.STAR, tokens, current, current+1, line)
      case '!':
        addToken(TokenType.BANG_EQUAL if match('=', &current, source) else TokenType.BANG, tokens, current, current+1, line)
      case '=':
        addToken(TokenType.EQUAL_EQUAL if match('=', &current, source) else TokenType.EQUAL, tokens, current, current+1, line)
      case '<':
        addToken(TokenType.LESS_EQUAL if match('=', &current, source) else TokenType.LESS, tokens, current, current+1, line)
      case '>':
        addToken(TokenType.GREATER_EQUAL if match('=', &current, source) else TokenType.GREATER, tokens, current, current+1, line)
      case '/':
        if match('/', &current, source) {
          for peek(source, current) != rune('\n') && !(current >= len(source)) {
            current += 1
          }
        }
        else {
          addToken(TokenType.SLASH, tokens, current, current+1, line)
        }
      case '"':
        string_tokenize(source, &current, &line, tokens)
        break
      case ' ':
      case '\r':
      case '\t':
        break
      case '\n':
        line += 1
        break
      case:
        error(line, "Unexpected character")
        break
    }
  }
}

run :: proc(source : string) {
  tokens : [dynamic]Token
  scanTokens(source, &tokens)
  for token in tokens {
    fmt.println(token)
  }
}

runFile :: proc(filename : string) {
  data, err := os.read_entire_file_from_path(filename, context.allocator)
  if len(data) > 0 {
    defer delete(data)
  }
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
