## generic string functions ##

start(s::String) = 1
done(s::String,i) = (i > length(s))
ref(s::String, i::Index) = next(s,i)[1]
length(s::String) = at_string_end(s)[1]
strlen(s::String) = at_string_end(s)[2]
string(s::String) = s

print(c::Char) = (write(current_output_stream(), c); ())
print(s::String) = for c = s; print(c); end
show(s::String) = print(quote_string(s))

function size(s::String, d::Index)
    if d != 1
        error("in size: tupleref: index out of range")
    end
    length(s)
end

function at_string_end(s::String)
    n = 0
    i = start(s)
    while !done(s,i)
        c, i = next(s,i)
        n += 1
    end
    return i, n
end

(<) (a::String, b::String) = cmp(a,b) < 0
(>) (a::String, b::String) = cmp(a,b) > 0
(==)(a::String, b::String) = cmp(a,b) == 0
(<=)(a::String, b::String) = cmp(a,b) <= 0
(>=)(a::String, b::String) = cmp(a,b) >= 0

function cmp(a::String, b::String)
    i = start(a)
    j = start(b)
    while !done(a,i) && !done(b,i)
        c, i = next(a,i)
        d, j = next(b,j)
        if c != d
            return c < d ? -1 : +1
        end
    end
    done(a,i) && !done(b,j) ? -1 :
    !done(a,i) && done(b,j) ? +1 : 0
end

## plain old character arrays ##

struct CharString <: String
    chars::Array{Char,1}

    CharString(a::Array{Char,1}) = new(a)
    CharString(c::Char...) = new([ c[i] | i=1:length(c) ])
    CharString(x...) = CharString(map(char,x)...)
end

next(s::CharString, i::Index) = (s.chars[i], i+1)
length(s::CharString) = length(s.chars)

string(c::Char) = CharString(c)
string(c::Char, x::Char...) = CharString(c, x...)

## substrings reference original strings ##

struct SubString <: String
    string::String
    offset::Index
    length::Index

    SubString(s::String, i::Index, j::Index) = new(s, i-1, j-i+1)
    SubString(s::SubString, i::Index, j::Index) =
        new(s.string, s.offset+i-1, j-i+1)
end

function next(s::SubString, i::Index)
    if i < 1 || i > s.length
        error("string index out of bounds")
    end
    next(s.string,s.offset+i)
end

length(s::SubString) = s.length
# TODO: strlen(s::SubString) = ??
# default implementation will work but it's slow
# can this be delegated efficiently somehow?
# that may require additional string interfaces

ref(s::String, r::Range1{Index})    = SubString(s,r.start,r.stop)
ref(s::String, r::RangeFrom{Index}) = SubString(s,r.start,length(s))
ref(s::String, r::RangeTo{Index})   = SubString(s,1,r.stop)

function ref(s::String, r::RangeBy{Index})
    if r.step != 1
        error("only unit steps supported for string slices")
    end
    return s
end

## ropes for efficient concatenation, etc. ##

# Idea: instead of this standard binary tree structure,
# how about we keep an array of substrings, with and
# offset array. We can do binary search on the offset
# array so we get O(log(n)) indexing time still, but we
# can compute the offsets lazily and avoid all the
# futzing around while the string is being constructed.

struct RopeString <: String
    head::String
    tail::String
    depth::Int32
    length::Index

    RopeString(h::RopeString, t::RopeString) =
        depth(h.tail) + depth(t) < depth(h.head) ?
            RopeString(h.head, RopeString(h.tail, t)) :
            new(h, t, max(h.depth, t.depth)+1, length(h)+length(t))

    RopeString(h::RopeString, t::String) = depth(h.tail) < depth(h.head) ?
        RopeString(h.head, RopeString(h.tail, t)) :
        new(h, t, h.depth+1, length(h)+length(t))

    RopeString(h::String, t::RopeString) = depth(t.head) < depth(t.tail) ?
        RopeString(RopeString(h, t.head), t.tail) :
        new(h, t, t.depth+1, length(h)+length(t))

    RopeString(h::String, t::String) = new(h, t, 1, length(h)+length(t))
end

depth(s::String) = 0
depth(s::RopeString) = s.depth

# strtree(s::String) = print(".")
# function strtree(s::RopeString)
#     print("[")
#     strtree(s.head)
#     strtree(s.tail)
#     print("]")
# end

function next(s::RopeString, i::Index)
    if i <= length(s.head)
        return next(s.head, i)
    else
        c, j = next(s.tail, i-length(s.head))
        return c, j+length(s.head)
    end
end

length(s::RopeString) = s.length
strlen(s::RopeString) = strlen(s.head) + strlen(s.tail)

strcat() = ""
strcat(s::String) = s
strcat(s::String, t::String...) = RopeString(s, strcat(t...))
strcat(x...) = strcat(map(string,x)...)

print(s::RopeString) = print(s.head,s.tail)

## generic string utilities ##

function escape_string(s::String, q)
    e = q ? "\"" : ""
    i = start(s)
    while !done(s,i)
        c, j = next(s,i)
        z = !done(s,j) && '0' <= next(s,j)[1] <= '7' ? "\\000" : "\\0"
        d = c == '\0'    ? z :
            c == '\\'    ? "\\\\" :
            c == '\e'    ? "\\e" :
        q&& c == '\"'    ? "\\\"" :
            31 < c < 127 ? string(c) :
            7 <= c <= 13 ? string('\\',"abtnvfr"[c-6]) :
                           strcat("\\", uint2str(c,8,3))
        e = strcat(e,d)
        i = j
    end
    q ? strcat(e,"\"") : e
end

escape_string(s::String) = escape_string(s,false)
quote_string(s::String)  = escape_string(s,true)

# function unescape_string(esc::String)
#     raw = ""
#     i = 1
#     while i <= length(esc)
#         if i < length(esc) && esc[i] == "\\"
#             e = esc[i+1]
#             i += 2
#             c = e == "a" ?  7 :
#                 e == "b" ?  8 :
#                 e == "t" ?  9 :
#                 e == "n" ? 10 :
#                 e == "v" ? 11 :
#                 e == "f" ? 12 :
#                 e == "r" ? 13 :
#                 e == "e" ? 27 :
#                 e == "x" ? begin
#                     x = 0
#                     m = min(i+1,length(esc))
#                     while i <= m
#                         if "0" <= esc[i] <= "9"
#                             x = 16*x + ord(esc[i]) - ord("0")
#                         elseif "a" <= esc[i] <= "f"
#                             x = 16*x + ord(esc[i]) - ord("a") + 10
#                         elseif "A" <= esc[i] <= "F"
#                             x = 16*x + ord(esc[i]) - ord("A") + 10
#                         else
#                             break
#                         end
#                         i += 1
#                     end
#                     if esc[i-1] == "x"
#                         error("\\x used with no following hex digits")
#                     end
#                     x
#                 end :
#                 "0" <= e <= "7" ? begin
#                     x = ord(e) - ord("0")
#                     m = min(i+1,length(esc))
#                     while i <= m && "0" <= esc[i] <= "7"
#                         x = 8*x + ord(esc[i]) - ord("0")
#                         i += 1
#                     end
#                     if x > 255
#                         error("octal escape sequence out of range")
#                     end
#                     x
#                 end : ord(e)
#             raw += chr(c)
#         else
#             raw += esc[i]
#             i += 1
#         end
#     end
#     raw
# end

function lpad(s::String, n::Int, p)
    n <= length(s) && return s
    ps = s
    while length(ps) < n
        ps = strcat(p,ps)
    end
    ps[end-n+1:]
end

function rpad(s::String, n::Int, p)
    n <= length(s) && return s
    ps = s
    while length(ps) < n
        ps = strcat(ps,p)
    end
    ps[:n]
end

## string to integer functions ##

function parse_int(T::Type{Int}, s::String, base::Int)
    n = zero(T)
    base = convert(T,base)
    for c = s
        d = '0' <= c <= '9' ? c - '0' :
            'A' <= c <= 'Z' ? c - 'A' + 10 :
            'a' <= c <= 'z' ? c - 'a' + 10 :
            error("non alphanumeric digit")
        d = convert(T,d)
        if base <= d
            error("digit not valid in base")
        end
        n = n*base + d
    end
    return n
end

bin(s::String) = parse_int(Int64, s,  2)
oct(s::String) = parse_int(Int64, s,  8)
dec(s::String) = parse_int(Int64, s, 10)
hex(s::String) = parse_int(Int64, s, 16)

## bastard stuff that doesn't quite fit anywhere ##

function uint2str(n::Int, base::Int)
    ndig = n==convert(typeof(n),0) ? 1 : int32(floor(log(n)/log(base)+1))
    sz = ndig+1
    data = Array(Uint8, sz)
    ccall(dlsym(JuliaDLHandle,"uint2str"), Ptr{Uint8},
          (Ptr{Uint8}, Size, Uint64, Uint32),
          data, sz, uint64(n), uint32(base))
    UTF8String(data[:(sz-1)]) # cut out terminating NUL
end

uint2str(n::Int, base::Int, len::Int) = lpad(uint2str(n,base),len,"0")

function string(p::Ptr{Uint8})
    if p == C_NULL
        error("cannot convert NULL to string")
    end
    UTF8String(ccall(dlsym(JuliaDLHandle,"jl_cstr_to_array"),
                     Any, (Ptr{Uint8},), p)::Array{Uint8,1})
end

string(x) = string(ccall(dlsym(JuliaDLHandle,"jl_show_to_string"),
                         Ptr{Uint8}, (Any,), x))
