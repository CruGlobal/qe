$(function() {
  setUpJsHelpers();
	$(document).on('ajaxStart', function() {
		$('#status').show();
	}).on('ajaxComplete', function() {
		$('#status').hide();
		setUpJsHelpers();
	});

  $(document).on('click', '.link-show-xml', function() {
    div = $(this).closest('.choices_section')
    $('.xmlChoices', div).show();
    $('.link-show-csv', div).show();
    $('.link-show-xml', div).hide();
    $('.csvChoices', div).hide();
  });

  $(document).on('click', '.link-show-csv', function() {
    div = $(this).closest('.choices_section')
    $('.csvChoices', div).show();
    $('.link-show-xml', div).show();
    $('.link-show-csv', div).hide();
    $('.xmlChoices', div).hide();
  });


	$(document).on('click', '.lbOn', function() {
		if ($('#dialog-help')[0] == null) {
			$('body').append('<div id="dialog-help" style="display:none" title="Help!"><p><span id="dialog-help-message"></span></p></div>');
		}
		$.get($(this).attr('href'), function(content) {
			$('#dialog-help-message').html(content);
			$('#dialog-help').dialog({
				modal: true,
				width: 500,
				buttons: {
					Close: function() {
						$(this).dialog('close');
					}
				}
			});
		});
		return false;
	});

	$(document).on('click', '.close_prop', function() {
  	$('#element_form_' + $(this).attr('data-dom_id')).hide();
	  $('#element_' + $(this).attr('data-dom_id')).show();
		return false;
	});

	$(document).on('click', 'input[name=future_affect][type=radio]', function() {
    if ($(this).val() == "yes") {
      $(".future_answer, .future_target, .future_page").show();
    } else if ($(this).val() == "no") {
      $(".future_answer, .future_target, .future_page").hide();
      $('#element_conditional_id').val('');
      $(".future_target input").removeAttr("checked");
      $("#element_conditional_type_").attr("checked", "checked");
    }
  });

  $(document).on('click', "input[name='element[conditional_type]'][type=radio]", function() {
    if ($(this).val() == "Fe::Page") {
      $(".future_page").show();
    } else if ($(this).val() == "Fe::Element") {
      $(".future_page").hide();
    }
  });
});
// used by form designer

var currentTab = 'pages_list';

function switchTab(toTab) {
  if(currentTab != null) $('#tab-' + currentTab).removeClass('active');
  $('#tab-' + toTab).addClass('active');
  currentTab = toTab;
  if (toTab == 'pages_list') {
    setUpSortables();
  }
}

function selectPage() {
    el = $('#link-page-name');
    clearCurrentElement();
    el.addClass('active');
    switchTab('properties');

    if($('#page_label').length > 0) $('#page_label').focus();
}

function selectElement(id) {
    el = $(id);
    clearPageName();
    clearCurrentElement();
    el.addClass('active');
    // snapElementProperties(el);
    activeElement = id;
    switchTab('properties');

    // if( $('#element_label')) $('#element_label').focus();
}

function clearCurrentElement() {
    if (activeElement != '' && $(activeElement)) {
        $(activeElement).removeClass('active');
    }
}

function clearPageName() {
    $('#link-page-name').removeClass('active');
}

function snapElementProperties(el) {
    propsTop = Position.cumulativeOffset(el)[1] - 160;
    if (propsTop < 0) propsTop = 0;
    $('#panel-properties-element').css({'margin-top': propsTop});
}

function addError(id) {
    $('#' + id).addClassName('fieldWithErrors');
}

// convert label to slug
function updateSlug(source, dest) {
  label = $(source).val();
  slug = $(dest).val();
  if( label == null || slug == null) return;  // oh oh

  label = label.strip();
  slug = slug.strip();

  if( label != '' && slug == '' ) {  // if slug is empty lets copy label to it
    slug = label.toLowerCase();
    slug = slug.gsub(/[^a-z0-9]/, '_');   // only alpha-numeric
    slug = slug.gsub(/_{2,}/, '_');       // compact double hyphens down to one
    slug = slug.gsub(/_$/, '');           // remove trailing underscores
    slug = slug.gsub(/^([0-9])/, '_\1')   // can't begin with a digit, so preprend an underscore
    if( slug.length > 36 ) slug = slug.slice(0, 36)  // max length

    $(dest).value = slug
    $(dest).focus();
  }
}

$(function() {
	setUpSortables();
	fixGridColumnWidths();
});
