_           = require("lodash")
assert      = require("assert")
path        = require("path")
util        = require("util")
vinylfs     = require("vinyl-fs")
coffee      = require("gulp-coffee")
plumber     = require("gulp-plumber")
acorn       = require("acorn")
walk        = require("acorn/util/walk")

amdOptimize = require("../lib/index")

dir = path.relative(process.cwd(), __dirname)


checkExpectedFiles = (expectedFiles, stream, done) ->

  expectedFiles = expectedFiles.slice(0)
  stream
    .on("data", (file) ->
      assert.equal(path.normalize(expectedFiles.shift()), file.relative)
    )
    .on("end", ->
      assert.equal(expectedFiles.length, 0)
      done()
    )

checkAst = (expectedFile, stream, tester, done) ->

  foundFile = false
  stream
    .on("data", (file) ->
      if file.relative == path.normalize(expectedFile)
        foundFile = true
        stringContents = file.contents.toString("utf8")
        ast = acorn.parse(stringContents)
        tester(ast, stringContents)
    )
    .on("end", ->
      assert.ok(foundFile, "Expected file '#{expectedFile}' not found.")
      done()
    )


describe "core", ->

  it "should work without configuration", (done) ->

    checkExpectedFiles(
      ["foo.js", "index.js"]
      vinylfs.src("#{dir}/fixtures/core/*.js")
        .pipe(amdOptimize("index"))
      done
    )


  it "should work with relative dependencies", (done) ->

    checkExpectedFiles(
      ["foo.js", "relative.js"]
      vinylfs.src("#{dir}/fixtures/core/*.js")
        .pipe(amdOptimize("relative"))
      done
    )


  it "should work with inline dependencies", (done) ->

    expectedFiles = ["foo.js", "bar.js", "inline.js"]

    counter = 0
    vinylfs.src("#{dir}/fixtures/core/*.js")
      .pipe(amdOptimize("inline"))
      .on("data", (file) ->
        if counter < 2
          assert(_.contains(expectedFiles[0..1], file.relative))
        else
          assert.equal(expectedFiles[2], file.relative)
        counter++
      )
      .on("end", ->
        assert.equal(counter, 3)
        done()
      )

  it "should work with `paths` config", (done) ->

    checkExpectedFiles(
      ["bar.js", "index.js"]

      vinylfs.src("#{dir}/fixtures/core/*.js")
        .pipe(amdOptimize(
          "index"
          paths : {
            foo : "bar"
          }
        ))

      done
    )


  it "should work with `map` config", (done) ->

    checkExpectedFiles(
      ["bar.js", "index.js"]

      vinylfs.src("#{dir}/fixtures/core/*.js")
        .pipe(amdOptimize(
          "index"
          map : {
            index : {
              foo : "bar"
            }
          }
        ))

      done
    )

  it "should only use forward slashes in module names", (done) ->

    checkAst(
      "fuz/ahah.js"
      vinylfs.src("#{dir}/fixtures/core/**/*.js")
        .pipe(amdOptimize("duu"))
      (ast) ->
        walk.simple(ast, CallExpression : (node) ->
          assert.equal(node.arguments[0].value, "fuz/ahah")
        )
      done
    )

  it "should remove the ast property when done", (done) ->

    vinylfs.src("#{dir}/fixtures/core/*.js")
      .pipe(amdOptimize("index"))
      .on("data", (file) ->
        assert(not ("ast" in file))
      )
      .on("end", done)


describe "src", ->

  it "should work with a default file loader", (done) ->

    checkExpectedFiles(
      ["foo.js", "index.js"]
      amdOptimize.src(
        "index"
        baseUrl : "test/fixtures/core"
      )
      done
    )


  it "should work with a custom file loader", (done) ->

    checkExpectedFiles(
      ["foo.js", "index.js"]
      amdOptimize.src(
        "index"
        loader : amdOptimize.loader((name) -> "#{dir}/fixtures/core/#{name}.js")
      )
      done
    )


  it "should work with a custom file loader with a pipe", (done) ->

    checkExpectedFiles(
      ["foo.js", "index.js"]
      amdOptimize.src(
        "index"
        loader : amdOptimize.loader(
          (name) -> "#{dir}/fixtures/core/#{name}.coffee"
          -> coffee()
        )
      )
      done
    )

  it "should look for files, if not piped in", (done) ->

    checkExpectedFiles(
      ["foo.js", "index.js"]
      vinylfs.src("#{dir}/fixtures/core/index.js")
        .pipe(amdOptimize(
          "index"
          baseUrl : "#{dir}/fixtures/core"
        ))
      done
    )


describe "include + exclude", ->

  it "should exclude modules and their dependency tree", (done) ->

    checkExpectedFiles(
      ["foo.js"]
      vinylfs.src("#{dir}/fixtures/inexclude/*.js")
        .pipe(amdOptimize(
          "foo"
          exclude : ["bar"]
        ))
      done
    )

  it "should shallowly exclude modules", (done) ->

    checkExpectedFiles(
      ["foo.js"]
      vinylfs.src("#{dir}/fixtures/inexclude/*.js")
        .pipe(amdOptimize(
          "foo"
          excludeShallow : ["baz"]
        ))
      done
    )

  it "should include modules even if they had been excluded"

  it "should include other modules"


describe "shim", ->

  it "should add a `define` for non-AMD modules", (done) ->

    vinylfs.src("#{dir}/fixtures/shim/*.js")
      .pipe(amdOptimize(
        "index"
      ))
      .on("data", (file) ->
        if file.relative == "no_amd.js"
          stringContents = file.contents.toString("utf8")
          assert(/define\(\s*["']no_amd['"]\s*/.test(stringContents))
      )
      .on("end", done)


  it "should add shimmed dependencies `define` for non-AMD modules", (done) ->

    vinylfs.src("#{dir}/fixtures/shim/*.js")
      .pipe(amdOptimize(
        "index"
        shim : {
          no_amd : {
            deps : ["no_amd2"]
          }
        }
      ))
      .on("data", (file) ->
        if file.relative == "no_amd.js"
          stringContents = file.contents.toString("utf8")
          assert(/define\(\s*["'].*['"]\s*,\s*\[\s*["']no_amd2["']\s*\]/.test(stringContents))
      )
      .on("end", done)


  it "should add shimmed export for non-AMD modules", (done) ->

    exportVariable = "test"

    vinylfs.src("#{dir}/fixtures/shim/*.js")
      .pipe(amdOptimize(
        "index"
        shim : {
          no_amd : {
            exports : exportVariable
          }
        }
      ))
      .on("data", (file) ->
        if file.relative == "no_amd.js"
          stringContents = file.contents.toString("utf8")
          ast = acorn.parse(stringContents)

          hasDefine = false
          walk.simple(ast, CallExpression : (node) ->

            if node.callee.name == "define"

              hasDefine = true

              funcNode = _.last(node.arguments)
              assert.equal(funcNode.type, "FunctionExpression")

              returnNode = _.last(funcNode.body.body)
              assert.equal(returnNode.type, "ReturnStatement")

              assert.equal(returnNode.argument.type, "Identifier")
              assert.equal(returnNode.argument.name, exportVariable)

          )
          assert(hasDefine)
      )
      .on("end", done)

  it "should wrap non-AMD modules with a `define` call", (done) ->

    exportVariable = "test"

    vinylfs.src("#{dir}/fixtures/shim/*.js")
      .pipe(amdOptimize(
        "no_amd"
        wrapShim : true
        shim : {
          no_amd : {
            exports : exportVariable
          }
        }
      ))
      .on("data", (file) ->
        if file.relative == "no_amd.js"
          stringContents = file.contents.toString("utf8")
          ast = acorn.parse(stringContents)

          assert.equal(ast.body[0].expression.type, "CallExpression")
          assert.equal(ast.body[0].expression.callee.name, "define")
      )
      .on("end", done)


  it "should wrap shimmed AMD modules with an immediately invoked function", (done) ->

    exportVariable = "test"

    vinylfs.src("#{dir}/fixtures/shim/*.js")
      .pipe(amdOptimize(
        "amd"
        wrapShim : true
        shim : {
          amd : {}
        }
      ))
      .on("data", (file) ->

        if file.relative == "amd.js"
          stringContents = file.contents.toString("utf8")
          ast = acorn.parse(stringContents)

          assert.equal(ast.body[0].expression.type, "CallExpression")
          assert.equal(ast.body[0].expression.callee.name, undefined)
          assert.equal(ast.body.length, 1)
      )
      .on("end", done)


  it "should not wrap non-shimmed modules", (done) ->

    vinylfs.src("#{dir}/fixtures/shim/*.js")
      .pipe(amdOptimize(
        "no_shim"
        wrapShim : true
      ))
      .on("data", (file) ->

        if file.relative == "no_shim.js"
          stringContents = file.contents.toString("utf8")
          ast = acorn.parse(stringContents)

          if ast.body[0].expression.type == "CallExpression"
            if ast.body[0].expression.callee.name == "define"
              assert.notEqual(ast.body[0].expression.arguments[0].value, "no_shim")
      )
      .on("end", done)


describe "nested dependencies", ->

  it "should not trace nested dependencies by default", (done) ->

    checkExpectedFiles(
      ["foo.js", "nested.js"]
      vinylfs.src("#{dir}/fixtures/core/*.js")
        .pipe(amdOptimize("nested"))
      done
    )


  it "should trace nested dependencies", (done) ->

    checkExpectedFiles(
      ["bar.js", "foo.js", "nested.js"]

      vinylfs.src("#{dir}/fixtures/core/*.js")
        .pipe(amdOptimize(
          "nested"
          findNestedDependencies : true
        ))

      done
    )


describe "config file", ->

  it "should read from config file from path", (done) ->

    checkExpectedFiles(
      ["index.js"]
      vinylfs.src("#{dir}/fixtures/config/index.js")
        .pipe(amdOptimize(
          "index"
          configFile : "#{dir}/fixtures/config/config.js"
        ))
      done
    )


  it "should read from config file from vinyl stream", (done) ->

    checkExpectedFiles(
      ["index.js"]
      vinylfs.src("#{dir}/fixtures/config/index.js")
        .pipe(amdOptimize(
          "index"
          configFile : vinylfs.src("#{dir}/fixtures/config/config.js")
        ))
      done
    )



describe "special paths", ->

  it "should ignore requirejs plugins", (done) ->

    checkExpectedFiles(
      ["bar.js", "plugin.js"]
      vinylfs.src("#{dir}/fixtures/core/*.js")
        .pipe(amdOptimize("plugin"))
      done
    )


  it "should ignore empty paths", (done) ->

    checkExpectedFiles(
      ["index.js"]
      vinylfs.src("#{dir}/fixtures/core/index.js")
        .pipe(amdOptimize(
          "index"
          paths : {
            foo : "empty:"
          }
        ))
      done
    )


  it "should apply prefix paths"


  it "should ignore `exports` and `require` dependencies", (done) ->

    checkExpectedFiles(
      ["bar.js", "require_exports.js"]
      vinylfs.src("#{dir}/fixtures/core/*.js")
        .pipe(amdOptimize("require_exports"))
      done
    )


describe "errors", ->

  it "should throw a meaningful error when JS files have a SyntaxError", (done) ->

    amdOptimize.src(
      "return"
      loader : amdOptimize.loader(
        (name) -> "#{dir}/fixtures/errors/#{name}.js"
      )
    ).on("error", (err) ->
      assert.ok(util.isError(err))
      assert.ok(err.filename)
      assert.ok(err.pos)
      done()
    )


  it "should passthrough the errors of loader streams", (done) ->

    amdOptimize.src(
      "foo"
      loader : amdOptimize.loader(
        (name) -> "#{dir}/fixtures/errors/#{name}.coffee"
        -> coffee()
      )
    ).on("error", (err) ->
      console.log(err)
      console.log(err.constructor)
      assert.ok(util.isError(err))
      done()
    )


  it "should throw a syntax error, when parsing goes wrong", (done) ->

    amdOptimize.src(
      "foo"
      baseUrl : "test/fixtures/errors"
    ).on("error", (err) ->
      assert.ok(util.isError(err))
      assert.equal("SyntaxError", err.name)
      done()
    )


  it "should throw an error on plain circular dependencies", (done) ->

    amdOptimize.src(
      "cycle1"
      baseUrl : "test/fixtures/errors"
    ).on("error", (err) ->
      assert.ok(util.isError(err))
      done()
    )


  it "should work with circular dependencies when exports is used"
  # , (done) ->
  #   # http://requirejs.org/docs/api.html#circular

  #   checkExpectedFiles(
  #     ["cycle_exports1.js", "cycle_exports2.js"]
  #     amdOptimize.src(
  #       "cycle_exports1"
  #       baseUrl : "test/fixtures/errors"
  #     )
  #     done
  #   )


describe "commonjs", ->

  it "should parse modules in simplified commonjs notation", (done) ->

    checkExpectedFiles(
      ["bar.js", "foo.js"]
      vinylfs.src("#{dir}/fixtures/commonjs/*.js")
        .pipe(amdOptimize("foo"))
      done
    )

