# frozen_string_literal: true

require 'json'

module FacadeCalculator
  VERSION = "1.0.0"
  REMOTE_BASE_URL = "https://raw.githubusercontent.com/byurii94/facade_calculator/main"

  def self.parse_float(val)
    return val.to_f if val.is_a?(Numeric)
    val.to_s.tr(',', '.').to_f
  end

  def self.parse_int(val)
    return val.to_i if val.is_a?(Numeric)
    val.to_s.tr(',', '.').to_i
  end

  def self.version_newer?(remote, local)
    r_parts = remote.split('.').map(&:to_i)
    l_parts = local.split('.').map(&:to_i)
    (r_parts <=> l_parts) == 1
  end

  def self.check_for_updates(silent: true)
    cache_bust = "t=#{Time.now.to_i}"
    req = Sketchup::Http::Request.new("#{REMOTE_BASE_URL}/version.json?#{cache_bust}", Sketchup::Http::GET)
    req.start do |_request, response|
      if response && response.status_code == 200
        begin
          data = JSON.parse(response.body)
          remote_ver = data["version"].to_s.strip
          if !remote_ver.empty? && version_newer?(remote_ver, VERSION)
            download_and_install_update(remote_ver)
          elsif !silent
            UI.messagebox("У вас уже встановлена актуальна версія (#{VERSION}).")
          end
        rescue => e
          UI.messagebox("Помилка перевірки оновлень: #{e.message}") unless silent
        end
      elsif !silent
        UI.messagebox("Не вдалося з'єднатися із сервером оновлень (код: #{response&.status_code}).")
      end
    end
  end

  def self.download_and_install_update(new_version)
    plugin_dir = File.dirname(__FILE__)
    cache_bust = "t=#{Time.now.to_i}"
    file_req = Sketchup::Http::Request.new("#{REMOTE_BASE_URL}/main.rb?#{cache_bust}", Sketchup::Http::GET)
    file_req.start do |_r, resp|
      if resp && resp.status_code == 200 && !resp.body.to_s.empty?
        File.binwrite(File.join(plugin_dir, "main.rb"), resp.body)
        UI.messagebox(
          "Калькулятор фасадів оновлено до версії #{new_version}!\n" \
          "Перезапустіть SketchUp, щоб зміни набули чинності."
        )
      else
        UI.messagebox("Не вдалося завантажити файл main.rb (код: #{resp&.status_code}).")
      end
    end
  end

  class FacadeTool
    def initialize(group, initial_params)
      @group = group
      @bb = group&.bounds
      @params = initial_params
      @direction = "Width"
    end

    def activate
      update_status
    end

    def deactivate(view)
      view.invalidate if view
    end

    def onKeyDown(key, repeat, flags, view)
      case key
      when 38, 63232 # Стрілка Вгору -> По висоті (шухляди)
        @direction = "Height"
        update_status
        view.invalidate if view
      when 37, 39, 63234, 63235 # Стрілки Вліво / Вправо -> По ширині (дверцята)
        @direction = "Width"
        update_status
        view.invalidate if view
      when 13 # Enter -> Створити фасади
        generate_facades
        Sketchup.active_model.select_tool(nil)
      when 27 # ESC -> Вихід
        UI.messagebox("Створення фасадів скасовано.")
        Sketchup.active_model.select_tool(nil)
      end
    end

    def update_status
      dir_text = (@direction == "Width") ? "ПО ШИРИНІ (Горизонтально / Дверцята)" : "ПО ВИСОТІ (Вертикально / Шухляди)"
      Sketchup.set_status_text("🗄️ КАЛЬКУЛЯТОР ФАСАДІВ | Напрямок: [ #{dir_text} ] | ⬆️ Вгору = Шухляди | ⬅️➡️ Вліво/Вправо = Дверцята | ENTER = Створити | ESC = Вихід")
    end

    def draw(view)
      return unless @bb && @group&.valid?

      dx = (@bb.max.x - @bb.min.x).to_mm
      dy = (@bb.max.y - @bb.min.y).to_mm
      dz = (@bb.max.z - @bb.min.z).to_mm

      axis_type = (dx >= dy) ? "X" : "Y"
      niche_height = dz
      niche_width  = (axis_type == "X") ? dx : dy

      facade_thickness = @params[:thickness]
      num_facades      = @params[:num_facades]
      gap_between      = @params[:gap_between]
      gap_left         = @params[:gap_left]
      gap_right        = @params[:gap_right]
      gap_top          = @params[:gap_top]
      gap_bottom       = @params[:gap_bottom]

      start_x = @bb.min.x
      start_y = @bb.min.y
      start_z = @bb.min.z

      view.drawing_color = Sketchup::Color.new(0, 120, 215)
      view.line_width = 2
      points = []

      if axis_type == "X"
        if @direction == "Width"
          available_width  = niche_width - (gap_left + gap_right)
          total_gaps_width = (num_facades - 1) * gap_between
          remaining_width  = available_width - total_gaps_width
          return if remaining_width <= 0

          facade_width  = remaining_width / num_facades
          facade_height = niche_height - (gap_top + gap_bottom)
          return if facade_height <= 0

          current_x = gap_left
          current_z = gap_bottom

          num_facades.times do
            x_abs = start_x + current_x.mm
            z_abs = start_z + current_z.mm
            fw = facade_width.mm
            ft = facade_thickness.mm
            fh = facade_height.mm

            p1 = Geom::Point3d.new(x_abs, start_y, z_abs)
            p2 = Geom::Point3d.new(x_abs + fw, start_y, z_abs)
            p3 = Geom::Point3d.new(x_abs + fw, start_y + ft, z_abs)
            p4 = Geom::Point3d.new(x_abs, start_y + ft, z_abs)

            z_top = z_abs + fh
            p5 = Geom::Point3d.new(x_abs, start_y, z_top)
            p6 = Geom::Point3d.new(x_abs + fw, start_y, z_top)
            p7 = Geom::Point3d.new(x_abs + fw, start_y + ft, z_top)
            p8 = Geom::Point3d.new(x_abs, start_y + ft, z_top)

            points.concat([p1, p2, p2, p3, p3, p4, p4, p1])
            points.concat([p5, p6, p6, p7, p7, p8, p8, p5])
            points.concat([p1, p5, p2, p6, p3, p7, p4, p8])

            current_x += facade_width + gap_between
          end
        else
          facade_width     = niche_width - (gap_left + gap_right)
          available_height = niche_height - (gap_top + gap_bottom)
          total_gaps_h     = (num_facades - 1) * gap_between
          remaining_height = available_height - total_gaps_h
          return if remaining_height <= 0

          facade_height = remaining_height / num_facades
          current_z     = gap_bottom

          num_facades.times do
            x_abs = start_x + gap_left.mm
            z_abs = start_z + current_z.mm
            fw = facade_width.mm
            ft = facade_thickness.mm
            fh = facade_height.mm

            p1 = Geom::Point3d.new(x_abs, start_y, z_abs)
            p2 = Geom::Point3d.new(x_abs + fw, start_y, z_abs)
            p3 = Geom::Point3d.new(x_abs + fw, start_y + ft, z_abs)
            p4 = Geom::Point3d.new(x_abs, start_y + ft, z_abs)

            z_top = z_abs + fh
            p5 = Geom::Point3d.new(x_abs, start_y, z_top)
            p6 = Geom::Point3d.new(x_abs + fw, start_y, z_top)
            p7 = Geom::Point3d.new(x_abs + fw, start_y + ft, z_top)
            p8 = Geom::Point3d.new(x_abs, start_y + ft, z_top)

            points.concat([p1, p2, p2, p3, p3, p4, p4, p1])
            points.concat([p5, p6, p6, p7, p7, p8, p8, p5])
            points.concat([p1, p5, p2, p6, p3, p7, p4, p8])

            current_z += facade_height + gap_between
          end
        end
      else
        if @direction == "Width"
          available_width  = niche_width - (gap_left + gap_right)
          total_gaps_width = (num_facades - 1) * gap_between
          remaining_width  = available_width - total_gaps_width
          return if remaining_width <= 0

          facade_width  = remaining_width / num_facades
          facade_height = niche_height - (gap_top + gap_bottom)
          return if facade_height <= 0

          current_y = gap_left
          current_z = gap_bottom

          num_facades.times do
            y_abs = start_y + current_y.mm
            z_abs = start_z + current_z.mm
            fw = facade_width.mm
            ft = facade_thickness.mm
            fh = facade_height.mm

            p1 = Geom::Point3d.new(start_x, y_abs, z_abs)
            p2 = Geom::Point3d.new(start_x, y_abs + fw, z_abs)
            p3 = Geom::Point3d.new(start_x + ft, y_abs + fw, z_abs)
            p4 = Geom::Point3d.new(start_x + ft, y_abs, z_abs)

            z_top = z_abs + fh
            p5 = Geom::Point3d.new(start_x, y_abs, z_top)
            p6 = Geom::Point3d.new(start_x, y_abs + fw, z_top)
            p7 = Geom::Point3d.new(start_x + ft, y_abs + fw, z_top)
            p8 = Geom::Point3d.new(start_x + ft, y_abs, z_top)

            points.concat([p1, p2, p2, p3, p3, p4, p4, p1])
            points.concat([p5, p6, p6, p7, p7, p8, p8, p5])
            points.concat([p1, p5, p2, p6, p3, p7, p4, p8])

            current_y += facade_width + gap_between
          end
        else
          facade_width     = niche_width - (gap_left + gap_right)
          available_height = niche_height - (gap_top + gap_bottom)
          total_gaps_h     = (num_facades - 1) * gap_between
          remaining_height = available_height - total_gaps_h
          return if remaining_height <= 0

          facade_height = remaining_height / num_facades
          current_z     = gap_bottom

          num_facades.times do
            y_abs = start_y + gap_left.mm
            z_abs = start_z + current_z.mm
            fw = facade_width.mm
            ft = facade_thickness.mm
            fh = facade_height.mm

            p1 = Geom::Point3d.new(start_x, y_abs, z_abs)
            p2 = Geom::Point3d.new(start_x, y_abs + fw, z_abs)
            p3 = Geom::Point3d.new(start_x + ft, y_abs + fw, z_abs)
            p4 = Geom::Point3d.new(start_x + ft, y_abs, z_abs)

            z_top = z_abs + fh
            p5 = Geom::Point3d.new(start_x, y_abs, z_top)
            p6 = Geom::Point3d.new(start_x, y_abs + fw, z_top)
            p7 = Geom::Point3d.new(start_x + ft, y_abs + fw, z_top)
            p8 = Geom::Point3d.new(start_x + ft, y_abs, z_top)

            points.concat([p1, p2, p2, p3, p3, p4, p4, p1])
            points.concat([p5, p6, p6, p7, p7, p8, p8, p5])
            points.concat([p1, p5, p2, p6, p3, p7, p4, p8])

            current_z += facade_height + gap_between
          end
        end
      end

      view.draw(GL_LINES, points) unless points.empty?
    end

    def generate_facades
      model = Sketchup.active_model
      entities = model.active_entities

      dx = (@bb.max.x - @bb.min.x).to_mm
      dy = (@bb.max.y - @bb.min.y).to_mm
      dz = (@bb.max.z - @bb.min.z).to_mm

      axis_type = (dx >= dy) ? "X" : "Y"
      niche_height = dz
      niche_width  = (axis_type == "X") ? dx : dy

      facade_thickness = @params[:thickness]
      num_facades      = @params[:num_facades]
      gap_between      = @params[:gap_between]
      gap_left         = @params[:gap_left]
      gap_right        = @params[:gap_right]
      gap_top          = @params[:gap_top]
      gap_bottom       = @params[:gap_bottom]

      start_x = @bb.min.x
      start_y = @bb.min.y
      start_z = @bb.min.z

      model.start_operation("Створення фасадів", true)

      main_group = entities.add_group
      main_group.name = "Комплект фасадів"
      container_entities = main_group.entities
      main_group.transformation = Geom::Transformation.translation([start_x, start_y, start_z])

      if axis_type == "X"
        if @direction == "Width"
          available_width  = niche_width - (gap_left + gap_right)
          total_gaps_width = (num_facades - 1) * gap_between
          remaining_width  = available_width - total_gaps_width

          if remaining_width <= 0
            UI.messagebox("Помилка: Завеликі зазори або кількість фасадів!")
            model.abort_operation
            return
          end

          facade_width  = remaining_width / num_facades
          facade_height = niche_height - (gap_top + gap_bottom)
          current_x     = gap_left
          current_z     = gap_bottom

          num_facades.times do |i|
            fg = container_entities.add_group
            fg.name = "Фасад #{i + 1}"
            fg.transformation = Geom::Transformation.translation([current_x.mm, 0, current_z.mm])
            f_ent = fg.entities
            face = f_ent.add_face([0, 0, 0], [facade_width.mm, 0, 0], [facade_width.mm, facade_thickness.mm, 0], [0, facade_thickness.mm, 0])
            face.reverse! if face.normal.z < 0
            face.pushpull(facade_height.mm)
            current_x += facade_width + gap_between
          end
          msg = "Успішно створено #{num_facades} фасадів!"
        else
          facade_width     = niche_width - (gap_left + gap_right)
          available_height = niche_height - (gap_top + gap_bottom)
          total_gaps_h     = (num_facades - 1) * gap_between
          remaining_height = available_height - total_gaps_h

          if remaining_height <= 0
            UI.messagebox("Помилка: Завеликі вертикальні зазори!")
            model.abort_operation
            return
          end

          facade_height = remaining_height / num_facades
          current_z     = gap_bottom

          num_facades.times do |i|
            fg = container_entities.add_group
            fg.name = "Фасад #{i + 1} (шухляда)"
            fg.transformation = Geom::Transformation.translation([gap_left.mm, 0, current_z.mm])
            f_ent = fg.entities
            face = f_ent.add_face([0, 0, 0], [facade_width.mm, 0, 0], [facade_width.mm, facade_thickness.mm, 0], [0, facade_thickness.mm, 0])
            face.reverse! if face.normal.z < 0
            face.pushpull(facade_height.mm)
            current_z += facade_height + gap_between
          end
          msg = "Успішно створено #{num_facades} фасадів (шухляди)!"
        end
      else
        if @direction == "Width"
          available_width  = niche_width - (gap_left + gap_right)
          total_gaps_width = (num_facades - 1) * gap_between
          remaining_width  = available_width - total_gaps_width

          if remaining_width <= 0
            UI.messagebox("Помилка: Завеликі зазори або кількість фасадів!")
            model.abort_operation
            return
          end

          facade_width  = remaining_width / num_facades
          facade_height = niche_height - (gap_top + gap_bottom)
          current_y     = gap_left
          current_z     = gap_bottom

          num_facades.times do |i|
            fg = container_entities.add_group
            fg.name = "Фасад бічний #{i + 1}"
            fg.transformation = Geom::Transformation.translation([0, current_y.mm, current_z.mm])
            f_ent = fg.entities
            face = f_ent.add_face([0, 0, 0], [0, facade_width.mm, 0], [facade_thickness.mm, facade_width.mm, 0], [facade_thickness.mm, 0, 0])
            face.reverse! if face.normal.z < 0
            face.pushpull(facade_height.mm)
            current_y += facade_width + gap_between
          end
          msg = "Успішно створено #{num_facades} бічних фасадів!"
        else
          facade_width     = niche_width - (gap_left + gap_right)
          available_height = niche_height - (gap_top + gap_bottom)
          total_gaps_h     = (num_facades - 1) * gap_between
          remaining_height = available_height - total_gaps_h

          if remaining_height <= 0
            UI.messagebox("Помилка: Завеликі вертикальні зазори!")
            model.abort_operation
            return
          end

          facade_height = remaining_height / num_facades
          current_z     = gap_bottom

          num_facades.times do |i|
            fg = container_entities.add_group
            fg.name = "Фасад бічний #{i + 1} (шухляда)"
            fg.transformation = Geom::Transformation.translation([0, gap_left.mm, current_z.mm])
            f_ent = fg.entities
            face = f_ent.add_face([0, 0, 0], [0, facade_width.mm, 0], [facade_thickness.mm, facade_width.mm, 0], [facade_thickness.mm, 0, 0])
            face.reverse! if face.normal.z < 0
            face.pushpull(facade_height.mm)
            current_z += facade_height + gap_between
          end
          msg = "Успішно створено #{num_facades} бічних фасадів (шухляди)!"
        end
      end

      if @group && @group.valid?
        entities.erase_entities(@group)
      end

      model.commit_operation
      UI.messagebox(msg)
    end
  end

  def self.calculate
    model = Sketchup.active_model
    selection = model.selection

    if selection.length != 1 || !selection[0].is_a?(Sketchup::Group)
      UI.messagebox("⚠️ Будь ласка, виділіть один бокс-проріз (групу) у проєкті, а потім натискайте кнопку!")
      return
    end

    prompts = [
      "Товщина фасаду (мм):",
      "Кількість фасадів (шт.):",
      "Зазор між фасадами (мм):",
      "Зазор зліва / спереду (мм):",
      "Зазор справа / ззаду (мм):",
      "Зазор зверху (мм):",
      "Зазор знизу (мм):"
    ]

    defaults = ["18", "3", "3", "2", "2", "2", "2"]

    input = UI.inputbox(prompts, defaults, "Параметри фасадів")
    return unless input

    params = {
      thickness:   parse_float(input[0]),
      num_facades: parse_int(input[1]),
      gap_between: parse_float(input[2]),
      gap_left:    parse_float(input[3]),
      gap_right:   parse_float(input[4]),
      gap_top:     parse_float(input[5]),
      gap_bottom:  parse_float(input[6])
    }

    if params[:num_facades] <= 0 || params[:thickness] <= 0
      UI.messagebox("Будь ласка, введіть коректні додатні значення.")
      return
    end

    tool = FacadeTool.new(selection[0], params)
    model.select_tool(tool)
  end
end

unless file_loaded?(__FILE__)
  UI.menu("Extensions").add_item("Калькулятор фасадів (3D)") { FacadeCalculator.calculate }
  UI.menu("Extensions").add_item("Калькулятор фасадів: Перевірити оновлення") { FacadeCalculator.check_for_updates(silent: false) }

  path = File.dirname(__FILE__)
  icon_16 = File.join(path, "images", "icon_16.png")
  icon_24 = File.join(path, "images", "icon_24.png")
  cmd = UI::Command.new("Калькулятор фасадів (3D)") { FacadeCalculator.calculate }
  cmd.small_icon = icon_16 if File.exist?(icon_16)
  cmd.large_icon = icon_24 if File.exist?(icon_24)

  toolbar = UI::Toolbar.new("Калькулятор фасадів")
  toolbar.add_item(cmd)
  toolbar.restore

  UI.start_timer(2.0, false) { FacadeCalculator.check_for_updates(silent: true) }

  file_loaded(__FILE__)
end