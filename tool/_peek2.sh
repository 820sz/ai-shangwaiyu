cd /d/readflow || exit 1
grep -n "原版没找到\|补搜\|官方搜索\|planQueries\|runPass(extraQuery)" lib/screens/input/free_search_screen.dart | head -20