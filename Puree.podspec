Pod::Spec.new do |s|
  s.name         = "Puree"
  s.version      = "3.0.0"
  s.summary      = "Awesome log collector"
  s.homepage     = "https://github.com/cookpad/Puree-Swift"
  s.license      = { :type => "MIT", :file => "LICENSE" }
  s.authors      = { "Tomohiro Moro" => "tomohiro-moro@cookpad.com", "Kohki Miki" => "koki-miki@cookpad.com" }
  s.platform     = :ios, "10.0"
  s.source       = { :git => "https://github.com/cookpad/Puree-Swift.git", :tag => "#{s.version}" }
  s.source_files  = "Sources/**/*.{h,swift}"
end
