->(comment, record) do
  return [record["account"].to_s].to_json unless comment
  comment.upcase.split(" ").map { |s| CGI.escape(s) }
end
